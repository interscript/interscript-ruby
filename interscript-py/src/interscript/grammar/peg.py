# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Closure-compiled PEG engine for grammar tables produced by parg_reader.py.

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
      pairs them with the tree in walk order. Span bookkeeping is
      confined to the rules whose fixpoint analysis says they can reach
      a span capture; the from/to captures themselves are appended in
      the same walk order the flattener sees.

    - FAILURE DIAGNOSTICS: the interpreter tracks the furthest position
      reached and, for the rules isc_parser.py names as `diag_rules`,
      every failure position — the raw state the two hand-parser error
      messages ("Unterminated string", keyword-in-item-position) are
      rendered from. Failures of rules outside `diag_rules` update only
      the furthest-position counter.

WO18 execution model — each rule table is compiled ONCE into a chain of
Python closures (no per-input node dispatch). The grammar semantics are
unchanged; what is compiled away is interpreter overhead:

    - FINAL VALUES: every sequence/repetition closure folds its parts
      exactly the way the flattener (CanFlatten) would fold the tagged
      list the tree-driven interpreter used to build — the intermediate
      tag list and the flatten re-walk are gone. A small fixed set of
      rules (`raw_rules`) keeps tagged values: rules referenced from a
      named position whose value can be an empty repetition/maybe (the
      named fold yields []/None there), where shape-sensitive action
      code observes the difference.

    - span bookkeeping compiled out of every subtree whose fixpoint
      analysis proves it cannot reach a span capture.

    - failure diagnostics recorded lazily: one farthest-position compare
      per failed rule application, plus a (pos, rule) log entry only for
      `diag_rules`; the tables isc_parser.py reads are rebuilt on the
      error path only.

    - NO packrat memoization: the corpus revisits a (rule, position)
      pair ~3% of the time, so the memo tables were pure overhead (and
      the replaced hand parser had none). Re-evaluation is
      observationally identical — same call order, equal values, same
      span tuples, same farthest maxima, and the same (position, rule)
      failure log after the per-name sequential dedup.

    - scanner fusion: a contiguous run of Lit/CharClass atoms (merged
      char-class alternatives, char-class repetitions, complement scans
      for `!guard`-guarded character repetitions, and rule references
      that resolve to such atoms) compiles into ONE scanner closure that
      matches the whole run and returns the same merged Slice the
      flattener would produce; a named capture over such a run produces
      the capture hash directly. Repetition bodies that start with
      one-char atom alternatives fold the whole atom run into one Slice
      per run (hybrid scan); the flattener joins consecutive string-like
      items wholesale, so run granularity is invisible.

    - literal alternatives compile to a first-character bucket table
      (ordered choice preserved within each bucket), and char-class
      alternatives merge into one range table (every branch yields the
      identical one-char Slice).

Recursive rules (a rule whose reference graph reaches itself — the ISC
grammar has exactly one) bind their body through a level of indirection;
every other rule body binds directly, in dependency order (rule bodies
may reference rules declared later in the table).
"""

from __future__ import annotations

from .parg_reader import Alt, Cap, CharClass, Lit, Pred, Ref, Rep, Seq


class Slice:
    """A matched span of input (parsanol Slice: offset + content)."""

    __slots__ = ("offset", "content")

    def __init__(self, offset: int, content: str) -> None:
        self.offset = offset
        self.content = content

    def __repr__(self) -> str:
        return f"Slice(offset={self.offset!r}, content={self.content!r})"


class PegError(Exception):
    """Raised when the root rule fails to consume the whole input."""

    def __init__(self, message: str, at: int) -> None:
        super().__init__(message)
        self.at = at


# The shared failure result. Its third slot is never read on failure
# (every consumer branches on result[0] first), so one tuple serves all
# failing applications and a failing node allocates nothing.
_FAIL = (False, None, -1)


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
# Compilation — grammar table -> closure chain (built once per table).
# ---------------------------------------------------------------------------

# Scanner segment encodings:
#   ("l", s, n)                    literal, consumes n chars
#   ("c", ranges, charset|None)    one-char class (charset: frozenset fast path)
#   ("r", body_segs, mn, mx)       greedy repetition of a contiguous atom run


def _merge_ranges(ranges) -> tuple:
    """Sort + coalesce a char-class's ranges (membership-preserving)."""
    out: list[tuple[int, int]] = []
    for lo, hi in sorted(ranges):
        if out and lo <= out[-1][1] + 1:
            if hi > out[-1][1]:
                out[-1] = (out[-1][0], hi)
        else:
            out.append((lo, hi))
    return tuple(out)


def _charset_for(ranges) -> frozenset | None:
    """A frozenset fast path for small multi-range classes."""
    if len(ranges) < 3:
        return None
    if sum(hi - lo + 1 for lo, hi in ranges) > 1024:
        return None
    return frozenset(chr(u) for lo, hi in ranges for u in range(lo, hi + 1))


def _ranges_difference(ranges, sub) -> tuple:
    """ranges minus the (sorted, coalesced) sub ranges — membership-wise."""
    out: list[tuple[int, int]] = []
    subs = sorted(sub)
    for lo, hi in sorted(ranges):
        cur = lo
        for slo, shi in subs:
            if shi < cur or slo > hi:
                continue
            if slo > cur:
                out.append((cur, min(slo - 1, hi)))
            cur = max(cur, shi + 1)
            if cur > hi:
                break
        if cur <= hi:
            out.append((cur, hi))
    return tuple(out)


class _Compiled:
    """The compiled form of one rule table (shared across parses)."""

    __slots__ = ("entries", "ix_of", "spanning", "raw_rules")

    def __init__(self, entries, ix_of, spanning, raw_rules) -> None:
        self.entries = entries  # rule ix -> entry closure
        self.ix_of = ix_of  # rule name -> ix
        self.spanning = spanning  # rule ix -> bool (subtree reaches a span capture)
        self.raw_rules = raw_rules  # frozenset: rules kept in tagged-value mode


def _collect_refs(node, acc):
    t = type(node)
    if t is Ref:
        acc.append(node.name)
    elif t is Seq or t is Alt:
        for ch in node.a:
            _collect_refs(ch, acc)
    elif t is Rep or t is Pred or t is Cap:
        _collect_refs(node.a, acc)
    return acc


def _compile_rules(rules: dict, span_names: frozenset, diag_rules: frozenset) -> _Compiled:
    names = list(rules)
    ix_of = {n: i for i, n in enumerate(names)}

    # Unknown rule references fail at compile time (the interpreter used
    # to raise PegError on first parse; the canonical grammar has none).
    for name in names:
        for ref in _collect_refs(rules[name], []):
            if ref not in ix_of:
                raise PegError(f"unknown rule {ref!r}", 0)

    # -- single-reference rule inlining (AST level) -----------------------
    # A rule referenced exactly once is a pure passthrough at its ref
    # site: the rule boundary adds only an entry call, a depth-count
    # increment and a failure-log entry. Inline its body into the ref
    # site. Diagnostics rules (their failure log feeds error rendering)
    # and the entry rule stay; cycles cannot form (substitution only
    # removes references).
    from collections import Counter

    def subst(node, repl):
        t = type(node)
        if t is Ref:
            return repl.get(node.name, node)
        if t is Seq:
            return Seq(tuple(subst(ch, repl) for ch in node.a))
        if t is Alt:
            return Alt(tuple(subst(ch, repl) for ch in node.a))
        if t is Rep:
            return Rep(subst(node.a, repl), node.min, node.max, node.maybe)
        if t is Pred:
            return Pred(node.positive, subst(node.a, repl))
        if t is Cap:
            return Cap(node.name, subst(node.a, repl))
        return node  # Lit / CharClass

    counts = Counter()
    for name in names:
        counts.update(_collect_refs(rules[name], []))
    while True:
        target = next(
            (
                n
                for n, k in counts.items()
                if k == 1 and n not in diag_rules and n in ix_of
            ),
            None,
        )
        if target is None:
            break
        holder = next(n for n in names if target in _collect_refs(rules[n], []))
        rules[holder] = subst(rules[holder], {target: rules[target]})
        counts = Counter()
        for name in names:
            counts.update(_collect_refs(rules[name], []))

    # -- span-reach fixpoint: which rules can record a span capture ------
    def node_reaches_span(node) -> bool:
        t = type(node)
        if t is Cap:
            return node.name in span_names or node_reaches_span(node.a)
        if t is Seq or t is Alt:
            for ch in node.a:
                if node_reaches_span(ch):
                    return True
            return False
        if t is Rep or t is Pred:
            return node_reaches_span(node.a)
        return False  # Lit / CharClass / Ref (refs via the fixpoint)

    spanning = [False] * len(names)
    changed = True
    while changed:
        changed = False
        for i, name in enumerate(names):
            v = node_reaches_span(rules[name]) or any(
                spanning[ix_of[r]] for r in _collect_refs(rules[name], [])
            )
            if spanning[i] != v:
                spanning[i] = v
                changed = True

    # -- atom rules: bodies that compile to a single contiguous matcher --
    # (Ref sites inside scanners inline these; other sites call normally.)
    atom_rule: dict[str, bool] = {}
    for name in names:
        body = rules[name]
        t = type(body)
        atom_rule[name] = (
            t is Lit
            or t is CharClass
            or (t is Alt and bool(body.a) and all(type(ch) is CharClass for ch in body.a))
        )

    def _min_chars(segs) -> int:
        total = 0
        for s in segs:
            if s[0] == "l":
                total += s[2]
            elif s[0] == "c":
                total += 1
            else:
                total += s[2] * _min_chars(s[1])
            if total > 0:
                return total  # exact enough for the consumes-at-least-one guard
        return total

    def seg_for(node):
        """Scanner segments for a contiguous atom run, or None.

        Returns a single segment tuple for atom-like nodes or a list of
        segments for sequences; every segment consumes at least one
        character except repetitions, whose own minimum is carried in
        the segment.
        """
        t = type(node)
        if t is Lit:
            s = node.s
            return ("l", s, len(s))
        if t is CharClass:
            ranges = _merge_ranges(node.ranges)
            return ("c", ranges, _charset_for(ranges))
        if t is Alt and node.a and all(type(ch) is CharClass for ch in node.a):
            ranges = _merge_ranges([r for ch in node.a for r in ch.ranges])
            return ("c", ranges, _charset_for(ranges))
        if t is Alt and node.a and all(type(ch) is Lit and len(ch.s) == 1 for ch in node.a):
            ranges = _merge_ranges([(ord(ch.s), ord(ch.s)) for ch in node.a])
            return ("c", ranges, _charset_for(ranges))
        if t is Ref:
            if atom_rule.get(node.name):
                return seg_for(rules[node.name])
            return None
        if t is Seq:
            segs = []
            for ch in node.a:
                s = seg_for(ch)
                if s is None:
                    return None
                segs.append(s)
            return segs if segs else None
        if t is Rep and not node.maybe:
            body = seg_for(node.a)
            if body is None:
                return None
            body_segs = body if isinstance(body, list) else [body]
            if _min_chars(body_segs) < 1:
                return None  # an empty-matchable body would loop forever
            return ("r", body_segs, node.min, node.max)
        return None

    # -- recursive rules (reference-graph reachability) --------------------
    direct_refs = {name: set(_collect_refs(rules[name], [])) for name in names}

    def reach_set(name) -> set:
        seen: set = set()
        stack = [name]
        while stack:
            for ref in direct_refs[stack.pop()]:
                if ref not in seen:
                    seen.add(ref)
                    stack.append(ref)
        return seen

    cyclic = [name for name in names if name in reach_set(name)]

    # -- closures ---------------------------------------------------------

    def c_lit(s, n):
        def lit(pos, I):
            if I.src.startswith(s, pos):
                end = pos + n
                if end > I.farthest:
                    I.farthest = end
                return (True, Slice(pos, s), end)
            return _FAIL

        return lit

    def c_cc(ranges, charset):
        def cc(pos, I):
            src = I.src
            if pos >= I.n:
                return _FAIL
            c = src[pos]
            u = ord(c)
            ok = charset is not None and u in charset
            if not ok:
                for lo, hi in ranges:
                    if lo <= u <= hi:
                        ok = True
                        break
            if not ok:
                return _FAIL
            end = pos + 1
            if end > I.farthest:
                I.farthest = end
            return (True, Slice(pos, c), end)

        return cc

    def c_alt_lits(buckets):
        get = buckets.get

        def alt_lit(pos, I):
            src = I.src
            if pos >= I.n:
                return _FAIL
            lits = get(src[pos])
            if lits is not None:
                for s, n in lits:
                    if src.startswith(s, pos):
                        end = pos + n
                        if end > I.farthest:
                            I.farthest = end
                        return (True, Slice(pos, s), end)
            return _FAIL

        return alt_lit

    def c_alt(children):
        def alt(pos, I):
            for f in children:
                r = f(pos, I)
                if r[0]:
                    return r
            return _FAIL

        return alt

    def c_alt_span(children):
        def alt(pos, I):
            spans = I.spans
            for f in children:
                mark = len(spans)
                r = f(pos, I)
                if r[0]:
                    return r
                if len(spans) != mark:
                    del spans[mark:]
            return _FAIL

        return alt

    def c_seq(children):
        def seq(pos, I):
            cur = pos
            parts = ["seq"]
            for f in children:
                r = f(cur, I)
                if not r[0]:
                    return _FAIL
                parts.append(r[1])
                cur = r[2]
            return (True, parts, cur)

        return seq

    def c_seq_span(children):
        def seq(pos, I):
            spans = I.spans
            cur = pos
            parts = ["seq"]
            mark = len(spans)
            for f in children:
                r = f(cur, I)
                if not r[0]:
                    if len(spans) != mark:
                        del spans[mark:]
                    return _FAIL
                parts.append(r[1])
                cur = r[2]
            return (True, parts, cur)

        return seq

    def c_rep(body, mn, mx, maybe):
        tag = "maybe" if maybe else "rep"

        def rep(pos, I):
            items = [tag]
            cur = pos
            count = 0
            while mx is None or count < mx:
                r = body(cur, I)
                if not r[0]:
                    break
                items.append(r[1])
                cur = r[2]
                count += 1
            if count < mn:
                if cur > I.farthest:
                    I.farthest = cur
                return _FAIL
            return (True, items, cur)

        return rep

    def c_rep_span(body, mn, mx, maybe):
        tag = "maybe" if maybe else "rep"

        def rep(pos, I):
            spans = I.spans
            items = [tag]
            cur = pos
            count = 0
            mark = len(spans)
            while mx is None or count < mx:
                mark_i = len(spans)
                r = body(cur, I)
                if not r[0]:
                    if len(spans) != mark_i:
                        del spans[mark_i:]
                    break
                items.append(r[1])
                cur = r[2]
                count += 1
            if count < mn:
                if cur > I.farthest:
                    I.farthest = cur
                if len(spans) != mark:
                    del spans[mark:]
                return _FAIL
            return (True, items, cur)

        return rep

    def c_rep_scan(ranges, charset, mn, mx, named=False, raw=False):
        # Pure char-class repetition: folds to the same value the generic
        # path's flatten produces (a joined Slice; an empty run folds to
        # "" — or, in a named position, [] — exactly what CanFlatten
        # yields for the tagged repetition at that position). Direct
        # named-capture bodies never take this path — they compile to
        # capture scanners, which carry the same fold. In raw (tagged)
        # rules the empty run returns the TAGGED list instead: a raw
        # rule's consumers may flatten it either way, and shape-sensitive
        # action code (actions.value_start) distinguishes [] from "".
        def rep(pos, I):
            src = I.src
            n = I.n
            cur = pos
            if charset is not None:
                cs = charset
                while cur < n and src[cur] in cs:
                    cur += 1
            else:
                while cur < n:
                    u = ord(src[cur])
                    ok = False
                    for lo, hi in ranges:
                        if lo <= u <= hi:
                            ok = True
                            break
                    if not ok:
                        break
                    cur += 1
            if mx is not None and cur - pos > mx:
                cur = pos + mx
            count = cur - pos
            if cur > I.farthest:
                I.farthest = cur
            if count < mn:
                return _FAIL
            if count == 0:
                if raw:
                    return (True, ["rep"], cur)
                return (True, [] if named else "", cur)
            return (True, Slice(pos, src[pos:cur]), cur)

        return rep

    def c_pred(body, positive):
        def pred(pos, I):
            spans = I.spans
            mark = len(spans)
            r = body(pos, I)
            # A lookahead never contributes captures: drop any match
            # spans its body recorded, success or failure (WO19: without
            # this, a speculative rule re-parse inside a lookahead leaks
            # from/to spans and desyncs the action layer's span walk).
            del spans[mark:]
            if r[0] is not positive:
                return _FAIL
            return (True, None, pos)

        return pred

    def c_rep_hybrid(ranges, charset, generics, mn, mx, maybe, final_named):
        # Repetition whose body is an alternation with one-char atom
        # branches first (merged into `ranges`) followed by generic
        # branches (`generics`: (closure, is_raw) pairs): whole unit runs
        # scan in one loop (one Slice per run), generic branches apply
        # per iteration. The item sequence is value-equivalent to the
        # per-iteration original: the flattener joins consecutive
        # string-like items wholesale, so a run Slice and per-char
        # Slices flatten identically (same join order, same offsets),
        # and hash/list classification never inspects them.
        # final_named is None in tagged (raw) mode — the tagged items
        # list is returned; otherwise it is the named flag for the
        # eager flatten (final mode).
        def rep(pos, I):
            src = I.src
            n = I.n
            if final_named is None:
                items = ["maybe" if maybe else "rep"]
            else:
                items = []
            cur = pos
            count = 0
            while mx is None or count < mx:
                run_start = cur
                if charset is not None:
                    cs = charset
                    while cur < n and src[cur] in cs:
                        cur += 1
                else:
                    while cur < n:
                        u = ord(src[cur])
                        ok = False
                        for lo, hi in ranges:
                            if lo <= u <= hi:
                                ok = True
                                break
                        if not ok:
                            break
                        cur += 1
                if cur > run_start:
                    if mx is not None and cur - run_start > mx - count:
                        cur = run_start + (mx - count)
                    if cur > I.farthest:
                        I.farthest = cur
                    items.append(Slice(run_start, src[run_start:cur]))
                    count += cur - run_start
                    if mx is not None and count >= mx:
                        break
                    continue
                matched = False
                for f, is_raw in generics:
                    r = f(cur, I)
                    if r[0]:
                        if is_raw and final_named is not None:
                            items.append(flatten(r[1], False))
                        else:
                            items.append(r[1])
                        cur = r[2]
                        count += 1
                        matched = True
                        break
                if not matched:
                    break
            if count < mn:
                if cur > I.farthest:
                    I.farthest = cur
                return _FAIL
            if final_named is None:
                return (True, items, cur)
            return (True, _flatten_repetition(items, final_named), cur)

        return rep

    def c_maybe_wrap(ranges, charset, generics):
        # `[x]` over a rule whose body is a run scanner / hybrid scanner
        # (`[ws]`): one application of the inner scanner, folded the way
        # the flattener folds it — every item is string-like (unit runs
        # are Slices; the guard requires it for the generic branches), so
        # the fold is one joined Slice from the start position, or "" for
        # zero width. The entry call, the item list and the fold all
        # collapse into this one closure.
        def rep(pos, I):
            src = I.src
            n = I.n
            cur = pos
            while True:
                run_start = cur
                if charset is not None:
                    cs = charset
                    while cur < n and src[cur] in cs:
                        cur += 1
                else:
                    while cur < n:
                        u = ord(src[cur])
                        ok = False
                        for lo, hi in ranges:
                            if lo <= u <= hi:
                                ok = True
                                break
                        if not ok:
                            break
                        cur += 1
                if cur > run_start:
                    continue
                matched = False
                for f in generics:
                    r = f(cur, I)
                    if r[0]:
                        cur = r[2]
                        matched = True
                        break
                if not matched:
                    break
            if cur > pos:
                if cur > I.farthest:
                    I.farthest = cur
                return (True, Slice(pos, src[pos:cur]), cur)
            return (True, "", pos)

        return rep

    def c_seq_final(children):
        # children: (closure, is_raw) pairs. The sequence's value is the
        # CanFlatten fold over its flattened parts — computed here once,
        # instead of building the tagged list and re-walking it later.
        def seq(pos, I):
            cur = pos
            parts: list = []
            for f, is_raw in children:
                r = f(cur, I)
                if not r[0]:
                    return _FAIL
                if is_raw:
                    parts.append(flatten(r[1], False))
                else:
                    parts.append(r[1])
                cur = r[2]
            return (True, _flatten_sequence(parts), cur)

        return seq

    def c_seq_final_span(children):
        # c_seq_final with span rollback: when a child fails, spans any
        # EARLIER sibling recorded must be dropped — the sequence never
        # happened. (WO19: the bare variant let a failed speculative
        # parse leak from/to spans, desyncing the action layer's span
        # walk on block rules carrying a `when` guard.)
        def seq(pos, I):
            spans = I.spans
            cur = pos
            parts: list = []
            mark = len(spans)
            for f, is_raw in children:
                r = f(cur, I)
                if not r[0]:
                    if len(spans) != mark:
                        del spans[mark:]
                    return _FAIL
                if is_raw:
                    parts.append(flatten(r[1], False))
                else:
                    parts.append(r[1])
                cur = r[2]
            return (True, _flatten_sequence(parts), cur)

        return seq

    def c_rep_final(body, body_raw, mn, mx, maybe, named):
        # The repetition's value is the CanFlatten fold over its
        # flattened items (named flag: direct capture bodies fold an
        # empty repetition to [] instead of ""). Same computation the
        # flattener performs on the tagged list, done here once. An
        # optional (`[x]`, maybe) folds like the flattener's maybe
        # branch: the single flattened item, or "" when it matched
        # nothing — never a list.
        def rep(pos, I):
            parts: list = []
            cur = pos
            count = 0
            while mx is None or count < mx:
                r = body(cur, I)
                if not r[0]:
                    break
                if body_raw:
                    parts.append(flatten(r[1], False))
                else:
                    parts.append(r[1])
                cur = r[2]
                count += 1
            if count < mn:
                if cur > I.farthest:
                    I.farthest = cur
                return _FAIL
            if maybe:
                first = parts[0] if parts else None
                if named or not (first is None or first == ""):
                    return (True, first, cur)
                return (True, "", cur)
            return (True, _flatten_repetition(parts, named), cur)

        return rep

    def c_rep_final_span(body, body_raw, mn, mx, maybe, named):
        # c_rep_final with span rollback: a failed iteration drops its
        # own partial spans; a rep that fails outright (count < mn) drops
        # every iteration's spans. (WO19, see c_seq_final_span.)
        def rep(pos, I):
            spans = I.spans
            parts: list = []
            cur = pos
            count = 0
            mark = len(spans)
            while mx is None or count < mx:
                mark_i = len(spans)
                r = body(cur, I)
                if not r[0]:
                    if len(spans) != mark_i:
                        del spans[mark_i:]
                    break
                if body_raw:
                    parts.append(flatten(r[1], False))
                else:
                    parts.append(r[1])
                cur = r[2]
                count += 1
            if count < mn:
                if cur > I.farthest:
                    I.farthest = cur
                if len(spans) != mark:
                    del spans[mark:]
                return _FAIL
            if maybe:
                first = parts[0] if parts else None
                if named or not (first is None or first == ""):
                    return (True, first, cur)
                return (True, "", cur)
            return (True, _flatten_repetition(parts, named), cur)

        return rep

    def c_cap(body, name, is_span_cap, body_raw):
        # body_raw: the body's value is a tagged list (a raw-marked rule)
        # that CanFlatten must resolve, with the named flag, before the
        # capture hash is built. Final bodies are already flattened.
        if is_span_cap:
            def cap(pos, I):
                spans = I.spans
                mark = len(spans)
                r = body(pos, I)
                if not r[0]:
                    if len(spans) != mark:
                        del spans[mark:]
                    return _FAIL
                spans.append((name, pos, r[2]))
                if body_raw:
                    return (True, {name: flatten(r[1], True)}, r[2])
                return (True, {name: r[1]}, r[2])

            return cap

        def cap(pos, I):
            r = body(pos, I)
            if not r[0]:
                return _FAIL
            if body_raw:
                return (True, {name: flatten(r[1], True)}, r[2])
            return (True, {name: r[1]}, r[2])

        return cap

    def match_unit(seg, src, cur, n):
        """Match one scanner unit; returns the new position or -1."""
        k = seg[0]
        if k == "l":
            if src.startswith(seg[1], cur):
                return cur + seg[2]
            return -1
        if cur >= n:
            return -1
        u = ord(src[cur])
        ok = seg[2] is not None and u in seg[2]
        if not ok:
            for lo, hi in seg[1]:
                if lo <= u <= hi:
                    ok = True
                    break
        return cur + 1 if ok else -1

    def match_segs(segs, src, cur, n):
        """Match a contiguous atom run; returns the end or -1."""
        for seg in segs:
            if seg[0] == "r":
                body, mn, mx = seg[1], seg[2], seg[3]
                start = cur
                while mx is None or cur - start < mx:
                    p = match_segs(body, src, cur, n)
                    if p < 0:
                        break
                    cur = p
                if cur - start < mn:
                    return -1
            else:
                cur = match_unit(seg, src, cur, n)
                if cur < 0:
                    return -1
        return cur

    def c_cap_scan(name, segs, is_span_cap, empty_value):
        def cap_scan(pos, I):
            src = I.src
            n = I.n
            cur = pos
            hi = pos  # high-water mark of matched positions (farthest state)
            failed = False
            for seg in segs:
                if seg[0] == "r":
                    body, mn, mx = seg[1], seg[2], seg[3]
                    start = cur
                    while mx is None or cur - start < mx:
                        p = match_segs(body, src, cur, n)
                        if p < 0:
                            break
                        cur = p
                    if cur > hi:
                        hi = cur
                    if cur - start < mn:
                        failed = True
                        break
                else:
                    p = match_unit(seg, src, cur, n)
                    if p < 0:
                        failed = True
                        break
                    cur = p
                    hi = cur
            if failed:
                if hi > I.farthest:
                    I.farthest = hi
                return _FAIL
            if hi > I.farthest:
                I.farthest = hi
            if is_span_cap:
                I.spans.append((name, pos, cur))
            if cur > pos:
                return (True, {name: Slice(pos, src[pos:cur])}, cur)
            return (True, {name: empty_value}, cur)

        return cap_scan

    def c_entry(name, body, diag):
        # No packrat memoization: the corpus revisits a (rule, position)
        # pair ~3% of the time, so the memo tables were pure overhead —
        # and the replaced hand parser (recursive descent) had none.
        # Re-evaluation is observationally identical: the same calls run
        # in the same order, producing equal values, the same span
        # tuples (the span delta replay existed only for memo hits), the
        # same farthest maxima (internal success notes only re-note
        # positions already noted on first evaluation), and the same
        # (position, rule) failure log entries (the per-name sequential
        # dedup absorbs the replayed duplicates the memo used to add).
        def entry(pos, I):
            depth = I.depth
            if depth >= 200:
                raise PegError(f"recursion limit exceeded in rule {name!r}", pos)
            I.depth = depth + 1
            r = body(pos, I)
            I.depth = depth
            if not r[0]:
                if pos > I.farthest:
                    I.farthest = pos
                if diag:
                    I.flog.append((pos, name))
            return r

        return entry

    # -- per-rule compilation ----------------------------------------------

    entries: list = [None] * len(names)

    def node_spanning(node) -> bool:
        """Whether this node's subtree can record a span capture (refs
        resolve to the rule-level fixpoint flags)."""
        t = type(node)
        if t is Ref:
            return spanning[ix_of[node.name]]
        if t is Cap:
            return node.name in span_names or node_spanning(node.a)
        if t is Seq or t is Alt:
            for ch in node.a:
                if node_spanning(ch):
                    return True
            return False
        if t is Rep or t is Pred:
            return node_spanning(node.a)
        return False  # Lit / CharClass

    def unit_class_of(node):
        """The merged ranges of a one-char matcher, or None.

        A one-char matcher is a char class (direct or an all-class
        alternation), a single-char literal (or all-single-char-literal
        alternation), or a reference to a rule whose body compiles to
        one. Every branch yields the identical one-char Slice, so the
        merged class matches exactly the same set with the same value.
        """
        t = type(node)
        if t is CharClass:
            return _merge_ranges(node.ranges)
        if t is Lit and len(node.s) == 1:
            return ((ord(node.s), ord(node.s)),)
        if t is Alt and node.a:
            if all(type(ch) is CharClass for ch in node.a):
                return _merge_ranges([r for ch in node.a for r in ch.ranges])
            if all(type(ch) is Lit and len(ch.s) == 1 for ch in node.a):
                return _merge_ranges([(ord(ch.s), ord(ch.s)) for ch in node.a])
        if t is Ref and atom_rule.get(node.name):
            seg = seg_for(rules[node.name])
            if seg is None:
                return None
            if seg[0] == "c":
                return seg[1]
            if seg[0] == "l" and seg[2] == 1:
                return ((ord(seg[1]), ord(seg[1])),)
        return None

    def rep_scan_of(body, mn, mx, named, raw):
        """Scan closures for pure char-class repetitions, or None.

        - Rep(class / all-class alt): the joined run.
        - Rep(seq(!one-char-guard, class)): the class run minus the
          guard set (the complement scan — raw_run / sq_body). The
          original's per-iteration items are [None, one-char Slice]
          sequence tags; the flattener resolves each to its slice and
          joins, which is exactly the scan's run Slice.
        """
        t = type(body)
        if t is CharClass:
            ranges = _merge_ranges(body.ranges)
            return c_rep_scan(ranges, _charset_for(ranges), mn, mx, named, raw)
        if t is Alt and body.a and all(type(ch) is CharClass for ch in body.a):
            ranges = _merge_ranges([r for ch in body.a for r in ch.ranges])
            return c_rep_scan(ranges, _charset_for(ranges), mn, mx, named, raw)
        if t is Seq and len(body.a) == 2:
            first, second = body.a
            if type(first) is Pred and not first.positive:
                guard = unit_class_of(first.a)
                inner = unit_class_of(second)
                if guard is not None and inner is not None:
                    diff = _ranges_difference(inner, guard)
                    return c_rep_scan(diff, _charset_for(diff), mn, mx, named, raw)
        return None

    # -- final-value mode: rules that must stay tagged --------------------
    # Every rule body compiles to its FINAL (already-flattened) value;
    # the flatten pass over tagged lists disappears. A rule keeps its
    # tagged value only when a consumer folds it with named=True: a
    # rule referenced from a named position (a capture body or an
    # alternation inside one) whose value can be an EMPTY tagged
    # repetition/maybe — the named fold yields []/None there, which the
    # rule's eager (named=False) fold cannot express.
    def bare_empty(node, seen):
        t = type(node)
        if t is Rep:
            return node.min == 0
        if t is Alt:
            for ch in node.a:
                if bare_empty(ch, seen):
                    return True
            return False
        if t is Ref:
            if node.name in seen:
                return False
            return bare_empty(rules[node.name], seen | {node.name})
        return False  # Lit / CharClass / Seq / Cap / Pred

    cap_named_refs: set = set()

    def mark_named(node, in_named):
        t = type(node)
        if t is Ref:
            if in_named:
                cap_named_refs.add(node.name)
            return
        if t is Cap:
            mark_named(node.a, True)
            return
        if t is Alt:
            for ch in node.a:
                mark_named(ch, in_named)
            return
        if t is Seq:
            for ch in node.a:
                mark_named(ch, False)
            return
        if t is Rep or t is Pred:
            mark_named(node.a, False)

    for name in names:
        mark_named(rules[name], False)

    raw_rules = frozenset(
        name for name in cap_named_refs if bare_empty(rules[name], frozenset())
    )

    def stringlike_final(node, seen):
        """Whether the node's FINAL value is always string-like (Slice
        or str). None parts inside a sequence fold are skipped by the
        fold, so they count there."""
        t = type(node)
        if t is Lit or t is CharClass or t is Pred:
            return True  # Slice / Slice / None (skipped by the fold)
        if t is Ref:
            if node.name in seen:
                return False
            return stringlike_final(rules[node.name], seen | {node.name})
        if t is Seq or t is Alt:
            for ch in node.a:
                if not stringlike_final(ch, seen):
                    return False
            return True
        if t is Rep:
            return not node.a or stringlike_final(node.a, seen)
        return False  # Cap (a hash)

    def _node_min_chars(node):
        t = type(node)
        if t is Lit:
            return len(node.s)
        if t is CharClass:
            return 1
        if t is Seq:
            return sum(_node_min_chars(ch) for ch in node.a)
        if t is Alt and node.a:
            return min(_node_min_chars(ch) for ch in node.a)
        if t is Rep:
            body = _node_min_chars(node.a)
            return node.min * body if body else 0
        if t is Cap or t is Pred:
            return 0
        if t is Ref:
            return _node_min_chars(rules[node.name])
        return 0

    def maybe_wrap_of(rule_name):
        """A fused `[x]` over a rule whose body is a run/hybrid scanner
        (`[ws]`): None when the shape does not apply. The wrap value is
        the maybe-fold of one inner application — every item string-like,
        hence one joined Slice or ""."""
        rb = rules[rule_name]
        if type(rb) is not Rep or rb.maybe or rb.min != 0 or rb.max is not None:
            return None
        inner = rb.a
        if not node_spanning(rb):
            scan = rep_scan_of(inner, rb.min, rb.max, False, False)
            if scan is not None:
                # one scan application; its zero-width value is "" —
                # exactly the maybe fold of a zero-width application
                return scan
        if type(inner) is Alt and inner.a and not node_spanning(rb):
            unit_ranges: list = []
            rest = list(inner.a)
            while rest:
                u = unit_class_of(rest[0])
                if u is None:
                    break
                unit_ranges.extend(u)
                rest.pop(0)
            if unit_ranges and rest and all(
                type(ch) is Ref
                and stringlike_final(rules[ch.name], frozenset({ch.name}))
                and _node_min_chars(rules[ch.name]) >= 1
                for ch in rest
            ):
                ranges = _merge_ranges(unit_ranges)
                generics = tuple(build(ch, False, False) for ch in rest)
                return c_maybe_wrap(ranges, _charset_for(ranges), generics)
        return None

    def build(node, raw=False, named=False):
        t = type(node)
        if t is Lit:
            return c_lit(node.s, len(node.s))
        if t is CharClass:
            ranges = _merge_ranges(node.ranges)
            return c_cc(ranges, _charset_for(ranges))
        if t is Alt:
            branches = node.a
            if branches and all(type(ch) is Lit for ch in branches):
                if all(ch.s for ch in branches):  # no empty literals
                    buckets: dict = {}
                    for ch in branches:
                        buckets.setdefault(ch.s[0], []).append((ch.s, len(ch.s)))
                    return c_alt_lits({k: tuple(v) for k, v in buckets.items()})
            if branches and all(type(ch) is CharClass for ch in branches):
                ranges = _merge_ranges([r for ch in branches for r in ch.ranges])
                return c_cc(ranges, _charset_for(ranges))
            children = tuple(build(ch, raw, named) for ch in branches)
            # WO19: a spanning alternation whose branch fails after a
            # later branch's span caps recorded must roll them back.
            if node_spanning(node):
                return c_alt_span(children)
            return c_alt(children)
        if t is Seq:
            if raw:
                children = tuple(build(ch, True, False) for ch in node.a)
                return c_seq(children)
            children = tuple(
                (build(ch, False, False), type(ch) is Ref and ch.name in raw_rules)
                for ch in node.a
            )
            if node_spanning(node):
                return c_seq_final_span(children)
            return c_seq_final(children)
        if t is Rep:
            body = node.a
            if not node.maybe:
                scan = rep_scan_of(body, node.min, node.max, named, raw)
                if scan is not None:
                    return scan
            if (
                not raw
                and node.maybe
                and node.min == 0
                and node.max == 1
                and type(body) is Ref
                and not node_spanning(node)
            ):
                wrap = maybe_wrap_of(body.name)
                if wrap is not None:
                    return wrap
            if not node.maybe and type(body) is Alt and body.a and not node_spanning(node):
                # hybrid scan: leading one-char atom branches merge into a
                # unit run; the remaining branches stay per-iteration
                unit_ranges: list = []
                rest = list(body.a)
                while rest:
                    u = unit_class_of(rest[0])
                    if u is None:
                        break
                    unit_ranges.extend(u)
                    rest.pop(0)
                if unit_ranges and rest:
                    ranges = _merge_ranges(unit_ranges)
                    if raw:
                        generics = tuple((build(ch, True, named), False) for ch in rest)
                        return c_rep_hybrid(
                            ranges, _charset_for(ranges), generics,
                            node.min, node.max, node.maybe, None,
                        )
                    generics = tuple(
                        (build(ch, False, named), type(ch) is Ref and ch.name in raw_rules)
                        for ch in rest
                    )
                    return c_rep_hybrid(
                        ranges, _charset_for(ranges), generics,
                        node.min, node.max, node.maybe, named,
                    )
            if raw:
                return c_rep(build(body, True, False), node.min, node.max, node.maybe)
            body_raw = type(body) is Ref and body.name in raw_rules
            if node_spanning(node):
                return c_rep_final_span(
                    build(body, False, False), body_raw, node.min, node.max, node.maybe, named
                )
            return c_rep_final(
                build(body, False, False), body_raw, node.min, node.max, node.maybe, named
            )
        if t is Pred:
            return c_pred(build(node.a, raw, False), node.positive)
        if t is Cap:
            segs = seg_for(node.a)
            if segs is not None:
                if isinstance(segs, list):
                    empty_value = ""  # sequence body: an empty textual run folds to ""
                else:
                    segs = [segs]
                    empty_value = []  # direct repetition body: named empty -> []
                return c_cap_scan(node.name, segs, node.name in span_names, empty_value)
            body_node = node.a
            span_cap = node.name in span_names
            if raw:
                return c_cap(build(body_node, True, True), node.name, span_cap, True)
            body_raw = type(body_node) is Ref and body_node.name in raw_rules
            # The capture body is a named position intrinsically: a direct
            # repetition/alternation body folds with named=True (its eager
            # fold must yield [] on an empty run), a sequence body does
            # not (its children fold with named=False either way).
            child_named = not body_raw and type(body_node) in (Rep, Alt)
            return c_cap(build(body_node, False, child_named), node.name, span_cap, body_raw)
        if t is Ref:
            return entries[ix_of[node.name]]
        raise TypeError(f"BUG: unknown PegNode {node!r}")

    # Recursive rules get their entries first (refs bind to them), with
    # the body threaded through a one-slot cell; acyclic rules then
    # compile in dependency order (a rule body may reference rules
    # declared later in the table), with direct body binding.
    cells: dict[str, list] = {}
    for name in cyclic:
        ix = ix_of[name]
        cell = [None]
        cells[name] = cell
        entries[ix] = c_entry(
            name, (lambda p, I, _c=cell: _c[0](p, I)), name in diag_rules
        )
    remaining = [name for name in names if entries[ix_of[name]] is None]
    built = {name for name in cyclic}
    while remaining:
        progressed = False
        still: list = []
        for name in remaining:
            if all(d in built for d in direct_refs[name]):
                body = build(rules[name], raw=name in raw_rules)
                entries[ix_of[name]] = c_entry(
                    name, body, name in diag_rules
                )
                built.add(name)
                progressed = True
            else:
                still.append(name)
        if not progressed:
            raise RuntimeError(f"grammar build order unresolved for: {still!r}")
        remaining = still
    for name, cell in cells.items():
        cell[0] = build(rules[name], raw=name in raw_rules)

    return _Compiled(entries, ix_of, spanning, raw_rules)


# Per-rule-table compile cache: id -> (rules, span_names, diag_rules,
# compiled). The rules reference is kept alive so its id is never reused.
_COMPILE_CACHE: dict = {}


def _compiled_for(rules: dict, span_names: frozenset, diag_rules: frozenset) -> _Compiled:
    key = id(rules)
    hit = _COMPILE_CACHE.get(key)
    if hit is not None and hit[0] is rules and hit[1] == span_names and hit[2] == diag_rules:
        return hit[3]
    compiled = _compile_rules(rules, span_names, diag_rules)
    _COMPILE_CACHE[key] = (rules, span_names, diag_rules, compiled)
    return compiled


# ---------------------------------------------------------------------------
# Interpreter — per-parse state over the compiled closures.
# ---------------------------------------------------------------------------


class PegInterpreter:
    MAX_DEPTH = 200

    def __init__(
        self,
        rules: dict,
        src: str,
        span_names: frozenset[str] = frozenset(),
        diag_rules: frozenset[str] = frozenset(),
    ) -> None:
        compiled = _compiled_for(rules, span_names, diag_rules)
        self._compiled = compiled
        # Per-parse state, read by the compiled closures. Attribute names
        # are part of the closure contract.
        self.src = src
        self.n = len(src)
        self.farthest = 0
        self.depth = 0
        # (name, start, end) of successful span-tracked captures, parse order.
        self.spans: list[tuple[str, int, int]] = []
        # Failure log: (pos, rule) for diag_rules failures, in parse order;
        # rebuilt into the diagnostic tables on the error path only.
        self.flog: list[tuple[int, str]] = []
        self._diag: tuple[set, dict] | None = None

    # -- entry ------------------------------------------------------------

    def parse_root(self, root: str, start: int = 0) -> tuple[object, int]:
        """Parse from `start`, requiring the ROOT rule plus full input
        consumption. Returns (flattened capture tree, end position)."""
        ix = self._compiled.ix_of.get(root)
        if ix is None:
            raise PegError(f"unknown rule {root!r}", start)
        r = self._compiled.entries[ix](start, self)
        if not r[0] or r[2] != self.n:
            at = r[2] if r[0] else self.farthest
            raise PegError(self._describe_failure(root, at), at)
        value = r[1] if root not in self._compiled.raw_rules else flatten(r[1])
        return value, r[2]

    def _describe_failure(self, root: str, at: int) -> str:
        line = self.src.count("\n", 0, at) + 1
        col = at - self.src.rfind("\n", 0, at)
        return f"Failed to match {root} at line {line} char {col}"

    # -- failure diagnostics (error-path only) ------------------------------

    def _build_diag(self) -> tuple[set, dict]:
        failed_rules: set[str] = set()
        failed_positions: dict[str, list[int]] = {}
        for pos, name in self.flog:
            failed_rules.add(name)
            positions = failed_positions.setdefault(name, [])
            if not positions or positions[-1] != pos:
                positions.append(pos)
        return failed_rules, failed_positions

    @property
    def failed_rules(self) -> set:
        if self._diag is None:
            self._diag = self._build_diag()
        return self._diag[0]

    @property
    def failed_positions(self) -> dict:
        if self._diag is None:
            self._diag = self._build_diag()
        return self._diag[1]
