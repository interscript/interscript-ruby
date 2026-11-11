# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""PEG interpreter for grammar tables produced by parg_reader.py.

Reproduces the parsanol (parslet-lineage) execution and tree-building
semantics exactly (mirroring interscript-ts's src/isc/grammar/peg.ts):

    - PEG ordered choice with full backtracking ACROSS alternatives, but
      possessive repetition (a failed iteration never unwinds earlier ones)
    - zero-width lookaheads (`!x` negative, `&x` positive)
    - values are: Slice (matched text + offset), capture dict, list, None
    - flattening (CanFlatten): a sequence folds its parts — string-likes
      coalesce, a string-like meeting a hash/list is dropped, hashes merge
      (later keys win), lists concat; a repetition containing hashes keeps
      only the hashes (bare strings are discarded), one containing lists
      flattens the lists, a purely textual one joins into one Slice; an
      unnamed optional that matched nothing yields ""

The result is the parslet-shaped capture tree the interscript-ruby
artifact parser produces, which the action layer (actions.py) then turns
into an IscDocument.

Two additions over the ts interpreter, both needed for hand-parser
parity (see isc_parser.py):

    - SPAN RECORDING: Cap nodes whose name is in `span_names` record
      (name, start, end) of their successful match, in parse order. The
      compact rule's from/to atoms carry no delimiters in the capture
      tree (closing quotes/brackets are not captured), but the W2
      override key is the byte-exact source text of the from atom — so
      the interpreter reports the exact match spans and the action layer
      pairs them with the tree in walk order. Memoized rule applications
      store and replay their span delta, so memoization stays sound.

    - FAILURE DIAGNOSTICS: the interpreter tracks the furthest position
      reached, the rule names that failed there, and every rule name that
      failed anywhere, so isc_parser.py can render the two hand-parser
      error messages the suite pins ("Unterminated string", keyword-in-
      item-position) from real parse state instead of string matching.
"""

from __future__ import annotations

from dataclasses import dataclass

from .parg_reader import Alt, Cap, CharClass, Lit, Pred, Ref, Rep, Seq


@dataclass(frozen=True, slots=True)
class Slice:
    """A matched span of input (parsanol Slice: offset + content)."""

    offset: int
    content: str


class PegError(Exception):
    """Raised when the root rule fails to consume the whole input."""

    def __init__(self, message: str, at: int) -> None:
        super().__init__(message)
        self.at = at


# ---------------------------------------------------------------------------
# Flattening — direct port of Parsanol::CanFlatten.
# ---------------------------------------------------------------------------


def flatten(value: object, named: bool = False) -> object:
    if not isinstance(value, list):
        return value
    tag = value[0]

    if len(value) == 2:
        f = flatten(value[1], False)
        if tag == "seq":
            return f
        if tag == "maybe":
            # JS `f || ""`: only null/"" collapse; hashes and lists pass
            # through (they are always truthy in JS).
            return f if named else (f if not (f is None or f == "") else "")
        if tag == "rep":
            return _flatten_repetition([f], named)

    n = len(value) - 1
    result = [flatten(value[i + 1], False) for i in range(n)]

    if tag == "seq":
        return _flatten_sequence(result)
    if tag == "maybe":
        first = result[0] if result else None
        return first if named else (first if not (first is None or first == "") else "")
    if tag == "rep":
        return _flatten_repetition(result, named)
    raise ValueError(f"BUG: unknown flatten tag {tag!r}")


def _flatten_sequence(lst: list) -> object:
    # foldl: skip leading nils, merge the rest left-to-right.
    i = 0
    n = len(lst)
    while i < n and lst[i] is None:
        i += 1
    if i >= n:
        return ""
    acc = lst[i]
    i += 1
    while i < n:
        e = lst[i]
        if e is not None:
            acc = _merge_fold(acc, e)
        i += 1
    return acc


def _is_hash(v: object) -> bool:
    return isinstance(v, dict)


def _is_stringlike(v: object) -> bool:
    return isinstance(v, (str, Slice))


def _slice_content(v: object) -> str:
    return v.content if isinstance(v, Slice) else v  # type: ignore[return-value,union-attr]


def _merge_fold(l: object, r: object) -> object:
    l_hash = _is_hash(l)
    r_hash = _is_hash(r)
    l_str = _is_stringlike(l)
    r_str = _is_stringlike(r)

    # equal pairs: merge
    if l_hash and r_hash:
        return {**l, **r}  # type: ignore[dict-item,union-attr]
    if isinstance(l, list) and isinstance(r, list):
        return [*l, *r]
    if isinstance(l, Slice) and isinstance(r, Slice):
        return Slice(l.offset, l.content + r.content)
    if isinstance(l, str) and isinstance(r, str):
        return l + r
    if l_str and r_str:
        # Mixing a plain string with a Slice keeps the slice (its offset).
        return r if isinstance(r, Slice) else l
    # unequal pairs: a string-like meeting a structured value drops itself
    if r_str:
        return l
    if l_str:
        return r
    # hash/list hoisting
    if _is_hash(r):
        return [l, r]
    if _is_hash(l):
        return [l, *r]  # type: ignore[misc]
    raise ValueError(f"BUG: unhandled merge_fold case ({type(l).__name__} / {type(r).__name__})")


def _flatten_repetition(lst: list, named: bool) -> object:
    has_hash = False
    has_array = False
    for e in lst:
        if _is_hash(e):
            has_hash = True
        elif isinstance(e, list):
            has_array = True
    if has_hash:
        return [e for e in lst if _is_hash(e)]
    if has_array:
        flat: list = []
        for e in lst:
            if isinstance(e, list):
                flat.extend(e)
        return flat
    if named and not lst:
        return []
    # All-string repetition: join into one slice.
    first: Slice | None = None
    content: str | None = None
    for e in lst:
        if e is None:
            continue
        if first is None and isinstance(e, Slice):
            first = e
        piece = _slice_content(e)
        content = piece if content is None else content + piece
    if content is None:
        return ""
    if first is not None:
        return Slice(first.offset, content)
    return content


# ---------------------------------------------------------------------------
# Interpreter
# ---------------------------------------------------------------------------


def _has_zero_named_charclass_rep(rules: dict) -> bool:
    """Shape guard for the Rep(CharClass) scan fast path. The fast path
    returns the repetition's FLATTENED value directly (a joined Slice, or
    "" when zero iterations), which is identical to the slow path's
    flatten EXCEPT for a zero-capable repetition sitting DIRECTLY under a
    named capture (flatten yields [] there, not ""). No such shape exists
    in the canonical ISC grammar; if a future grammar edit introduces
    one, the guard disables the fast path for the whole table instead of
    silently changing tree shapes."""

    def walk(node: object) -> bool:
        if isinstance(node, Cap):
            inner = node.a
            if (
                isinstance(inner, Rep)
                and not inner.maybe
                and inner.min == 0
                and isinstance(inner.a, CharClass)
            ):
                return True
            return walk(inner)
        if isinstance(node, (Seq, Alt)):
            return any(walk(child) for child in node.a)
        if isinstance(node, Pred):
            return walk(node.a)
        return False

    return any(walk(node) for node in rules.values())


class PegInterpreter:
    MAX_DEPTH = 200

    def __init__(
        self,
        rules: dict,
        src: str,
        span_names: frozenset[str] = frozenset(),
    ) -> None:
        self._rules = rules
        self._src = src
        self._span_names = span_names
        # Per-rule memo tables (rule order assigned lazily; pos -> result
        # tuple). Memo values: (ok, value, end_pos, spans_delta, fail_name).
        self._rule_ix: dict[int, int] = {}
        self._memo: list[dict[int, tuple]] = []
        self.farthest = 0
        self.depth = 0
        # (name, start, end) of successful span-tracked captures, parse order.
        self.spans: list[tuple[str, int, int]] = []
        # Rule names that failed AT the furthest position, and everywhere;
        # plus every failure position per rule name (bounded by the input
        # size) — the raw state the hand-parity error diagnostics read.
        self.failed_at_farthest: set[str] = set()
        self.failed_rules: set[str] = set()
        self.failed_positions: dict[str, list[int]] = {}
        # Rep(CharClass) scan fast path (see the Rep branch), disabled by
        # the shape guard when a tree-shape-changing pattern exists.
        self._fast_charclass_rep = not _has_zero_named_charclass_rep(rules)

    # -- entry ------------------------------------------------------------

    def parse_root(self, root: str, start: int = 0) -> tuple[object, int]:
        """Parse from `start`, requiring the ROOT rule plus full input
        consumption. Returns (flattened capture tree, end position)."""
        r = self._apply_rule(root, start)
        ok, value, pos = r[0], r[1], r[2]
        if not ok or pos != len(self._src):
            at = pos if ok else self.farthest
            raise PegError(self._describe_failure(root, at), at)
        return flatten(value), pos

    def _describe_failure(self, root: str, at: int) -> str:
        line = self._src.count("\n", 0, at) + 1
        col = at - self._src.rfind("\n", 0, at)
        return f"Failed to match {root} at line {line} char {col}"

    # -- bookkeeping --------------------------------------------------------

    def _note(self, pos: int) -> None:
        self.farthest = max(self.farthest, pos)

    def _note_failure(self, pos: int, name: str) -> None:
        self.failed_rules.add(name)
        positions = self.failed_positions.setdefault(name, [])
        if not positions or positions[-1] != pos:
            positions.append(pos)
        if pos > self.farthest:
            self.farthest = pos
            self.failed_at_farthest.clear()
        if pos == self.farthest:
            self.failed_at_farthest.add(name)

    # -- rules ----------------------------------------------------------------

    def _apply_rule(self, name: str, pos: int) -> tuple:
        ix = self._rule_ix.get(name)
        if ix is None:
            ix = self._rule_ix[name] = len(self._memo)
            self._memo.append({})
        table = self._memo[ix]
        hit = table.get(pos)
        if hit is not None:
            ok, value, r_pos, spans_delta, fail_name = hit
            if ok:
                if spans_delta:
                    self.spans.extend(spans_delta)
            else:
                self._note_failure(pos, fail_name)
            return (ok, value, r_pos)
        node = self._rules.get(name)
        if node is None:
            raise PegError(f"unknown rule {name!r}", pos)
        self.depth += 1
        if self.depth > self.MAX_DEPTH:
            self.depth -= 1
            raise PegError(f"recursion limit exceeded in rule {name!r}", pos)
        mark = len(self.spans)
        r = self._apply(node, pos, False)
        self.depth -= 1
        if r[0]:
            delta = tuple(self.spans[mark:]) if len(self.spans) != mark else ()
            memo = (True, r[1], r[2], delta, "")
        else:
            self._note_failure(pos, name)
            del self.spans[mark:]
            memo = (False, None, pos, (), name)
        table[pos] = memo
        return r

    # -- nodes ----------------------------------------------------------------

    def _apply(self, node: object, pos: int, consume_all: bool) -> tuple:
        # Dispatch ordered by measured hotness (Seq/Lit/CharClass dominate
        # the identifier/whitespace rules).
        kind = type(node)
        if kind is Seq:
            cur = pos
            parts: list = ["seq"]
            children = node.a  # type: ignore[union-attr]
            mark = len(self.spans)
            n = len(children)
            for i, child in enumerate(children):
                r = self._apply(child, cur, consume_all and i == n - 1)
                if not r[0]:
                    if len(self.spans) != mark:
                        del self.spans[mark:]
                    return (False, None, pos)
                parts.append(r[1])
                cur = r[2]
            return (True, parts, cur)
        if kind is Lit:
            s = node.s  # type: ignore[union-attr]
            src = self._src
            if src.startswith(s, pos):
                end = pos + len(s)
                self._note(end)
                return (True, Slice(pos, s), end)
            return (False, None, pos)
        if kind is CharClass:
            # Character classes match ONE code point (Python strings are
            # sequences of code points; the ts interpreter matches UTF-16
            # units and relies on textual repetitions rejoining surrogate
            # halves — same tree content either way). Every class in the
            # ISC grammar is BMP except the catch-all `chr` (%x00-10FFFF).
            src = self._src
            if pos >= len(src):
                return (False, None, pos)
            unit = ord(src[pos])
            for lo, hi in node.ranges:  # type: ignore[union-attr]
                if lo <= unit <= hi:
                    self._note(pos + 1)
                    return (True, Slice(pos, src[pos]), pos + 1)
            return (False, None, pos)
        if kind is Ref:
            return self._apply_rule(node.name, pos)  # type: ignore[union-attr]
        if kind is Rep:
            mn = node.min  # type: ignore[union-attr]
            mx = node.max  # type: ignore[union-attr]
            body = node.a  # type: ignore[union-attr]
            if (
                self._fast_charclass_rep
                and not node.maybe  # type: ignore[union-attr]
                and type(body) is CharClass
            ):
                # Scan fast path: a pure char-class repetition folds to the
                # same flattened value the slow path produces (a joined
                # Slice, or "" for zero iterations). Shape-guarded — see
                # _has_zero_named_charclass_rep.
                src = self._src
                ranges = body.ranges
                n = len(src)
                cur = pos
                while cur < n:
                    unit = ord(src[cur])
                    matched = False
                    for lo, hi in ranges:
                        if lo <= unit <= hi:
                            matched = True
                            break
                    if not matched:
                        break
                    cur += 1
                count = cur - pos
                if count < mn:
                    self._note(cur)
                    return (False, None, pos)
                self._note(cur)
                if count == 0:
                    return (True, "", cur)
                return (True, Slice(pos, src[pos:cur]), cur)
            tag = "maybe" if node.maybe else "rep"  # type: ignore[union-attr]
            items: list = [tag]
            cur = pos
            count = 0
            mark = len(self.spans)
            while mx is None or count < mx:
                mark_i = len(self.spans)
                r = self._apply(body, cur, False)
                if not r[0]:
                    if len(self.spans) != mark_i:
                        del self.spans[mark_i:]
                    break
                items.append(r[1])
                cur = r[2]
                count += 1
            if count < mn:
                self._note(cur)
                if len(self.spans) != mark:
                    del self.spans[mark:]
                return (False, None, pos)
            return (True, items, cur)
        if kind is Alt:
            for branch in node.a:  # type: ignore[union-attr]
                mark = len(self.spans)
                r = self._apply(branch, pos, consume_all)
                if r[0]:
                    return r
                if len(self.spans) != mark:
                    del self.spans[mark:]
            return (False, None, pos)
        if kind is Cap:
            mark = len(self.spans)
            r = self._apply(node.a, pos, consume_all)  # type: ignore[union-attr]
            if not r[0]:
                if len(self.spans) != mark:
                    del self.spans[mark:]
                return (False, None, pos)
            if node.name in self._span_names:  # type: ignore[union-attr]
                self.spans.append((node.name, pos, r[2]))  # type: ignore[union-attr]
            return (True, {node.name: flatten(r[1], True)}, r[2])  # type: ignore[union-attr]
        if kind is Pred:
            mark = len(self.spans)
            r = self._apply(node.a, pos, False)  # type: ignore[union-attr]
            if len(self.spans) != mark:
                del self.spans[mark:]  # zero-width: no capture survives a lookahead
            matched = r[0]
            if (node.positive and not matched) or (not node.positive and matched):  # type: ignore[union-attr]
                return (False, None, pos)
            # Zero-width: position unchanged, value None.
            return (True, None, pos)
        raise TypeError(f"BUG: unknown PegNode {node!r}")
