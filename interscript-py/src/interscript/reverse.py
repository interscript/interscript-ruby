# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Reverse mode — port of interscript-rs ``src/reverse.rs``, which
mirrors ``Interscript::Node::*#reverse`` (interscript-ruby origin/main,
spec'd by spec/reversibility_spec.rb).

The reversed document runs through the NORMAL executor: the inversion
lives entirely in the produced document. What rs does at the node
level, this module does at the compiled-map level:

- stages reverse (children in REVERSE order, each rule reversed);
- sub rules swap from/to, hoist boundary-like aliases across the
  transfer, and exchange capture groups/refs;
- ``to upcase``/``to downcase`` swap via Item#downcase/#upcase parity;
- funcalls map through the Ruby ``Stdlib.reverse_function`` table;
- the document name goes through ``Document.reverse_name``;
- metadata swaps source_script/destination_script;
- aliases, languages, tests (absent from the IR) pass through.

Documented ruby-crash deviations (rs ``Error::Unsupported``, mirrored
here as MapLogicError with the same information):

- a repeat item under a ``to upcase``/``to downcase`` sub
  (ruby: NoMethodError),
- a boundary hoist consuming the whole from group
  (ruby: NoMethodError on ``children=``),
- a funcall outside the reverse_function map (ruby: nil.to_sym
  TypeError when the reversed funcall executes),
- an unhandled item kind in the transfer walk (ruby: raise
  ``"Type ... unhandled!"``).

Compiled-IR deltas vs the rs node model (behavior identical):

- the compiled IR carries no ``reverse_run``; a rule whose reversed
  ``from`` is empty and has no assertions — which ruby marks
  reverse_run: true so the executor skips it — is DROPPED here
  (ruby's own JSON-IR compilers omit reverse_run rules too);
- dependency documents are names in the IR, so rs's recursion into
  embedded dependency documents lives on the runtime entry point
  (``Runtime.reverse``), not on this pure function;
- capture groups carry no ids: the regex engine numbers them in regex
  order at compile time, which is exactly the numbering rs's
  ``assign_group_ids`` reproduces; refs keep their numbers;
- ``priority`` (absent from the rs model) negates on reverse per ruby
  ``Sub#reverse``.
"""

from __future__ import annotations

from dataclasses import replace

from ._ir_types import (
    AnyCharClassItem,
    AnyItem,
    CaptureGroupItem,
    CaptureRefItem,
    CompiledMap,
    FuncallInline,
    FuncallRule,
    GroupItem,
    Item,
    ParallelRule,
    RepeatItem,
    Rule,
    SequentialRule,
    Stage,
    StringItem,
    SubRule,
)
from .errors import MapLogicError

# `Interscript::Stdlib.reverse_function`: the inverse funcall used by
# `Funcall#reverse`. `upcase` has no entry (the Ruby map omits it, so
# reversing an upcase funcall crashes there) — and any other funcall
# name is equally unmapped, mirroring rs's `FuncallName::reverse_name`.
REVERSE_FUNCTION: dict[str, str] = {
    # Those two are best-effort, but probably wrong (per Ruby).
    "title_case": "downcase",
    "downcase": "title_case",
    "compose": "decompose",
    "decompose": "compose",
    "separate": "unseparate",
    "unseparate": "separate",
}

# `Interscript::Stdlib.boundary_like_alias?` restricted to the prims rs
# treats as boundary-like (`Boundary`, `NonWordBoundary`, `LineStart`,
# `LineEnd` — the ISC grammar has no string_start/string_end
# spellings). Names as the ISC parser emits them.
BOUNDARY_LIKE_ALIASES: frozenset[str] = frozenset(
    {"boundary", "non_boundary", "non_word_boundary", "line_start", "line_end"}
)

# The compiled-IR form of ruby's `none` (converter lowering).
EMPTY_STRING = StringItem(value="")


def reverse_name(name: str) -> str:
    """`Interscript::Node::Document.reverse_name`: split on ``-``, swap
    positions 2/3 (source/target code) when there are at least 4
    segments; otherwise strip a ``-reverse`` suffix, otherwise append
    one."""
    parts = name.split("-")
    if len(parts) >= 4:
        swapped = list(parts)
        swapped[2], swapped[3] = swapped[3], swapped[2]
        joined = "-".join(swapped)
        if joined != name:
            return joined
    stripped = name.replace("-reverse", "")
    return stripped if stripped != name else f"{name}-reverse"


def reverse_map(map_: CompiledMap) -> CompiledMap:
    """`Interscript::Node::Document#reverse` over the compiled form.
    Aliases are NOT reversed (``rdoc.aliases = self.aliases``);
    dependency names pass through (see the module docstring for rs's
    dependency recursion and where it lives instead)."""
    return CompiledMap(
        schema_version=map_.schema_version,
        system_code=reverse_name(map_.system_code),
        dependencies=map_.dependencies,
        languages=map_.languages,
        metadata=_reverse_metadata(map_.metadata) if map_.metadata is not None else None,
        stages=tuple(_reverse_stage(s) for s in map_.stages),
        aliases=map_.aliases,
        functions=map_.functions,
    )


def _reverse_metadata(metadata: dict) -> dict:
    """`MetaData#reverse` swaps source_script/destination_script (each
    side only when the other is present — rs ``reverse_metadata``)."""
    src = metadata.get("source_script")
    dst = metadata.get("destination_script")
    out = dict(metadata)
    if "source_script" in out and dst is not None:
        out["source_script"] = dst
    if "destination_script" in out and src is not None:
        out["destination_script"] = src
    return out


def _reverse_stage(stage: Stage) -> Stage:
    """`Interscript::Node::Stage#reverse` / `Group#reverse`: children
    in REVERSE order, each reversed, reverse_run toggled. (The ISC
    grammar cannot express `dont_reverse`, so stages always reverse.)"""
    rules: list[Rule] = []
    for rule in reversed(stage.rules):
        # A sub whose reversed `from` is empty is dropped, not emitted
        # (see the module docstring — ruby marks it reverse_run: true).
        r = _reverse_rule(rule)
        if r is not None:
            rules.append(r)
    return Stage(name=stage.name, rules=tuple(rules))


def _reverse_rule(rule: Rule) -> Rule | None:
    """`None` = the reversed rule must not execute (ruby
    reverse_run: true)."""
    kind = rule.kind
    if kind == "sub":
        return _reverse_sub(rule)

    if kind == "run":
        # rs toggles reverse_run; the compiled IR carries none -> identity.
        return rule

    if kind == "funcall":
        # `Interscript::Node::Rule::Funcall#reverse`: the name maps
        # through `Stdlib.reverse_function`; kwargs carry over.
        target = REVERSE_FUNCTION.get(rule.name)
        if target is None:
            raise MapLogicError(
                f"funcall {rule.name} has no reverse (the Ruby reverse_function map omits it)"
            )
        return FuncallRule(name=target, kwargs=rule.kwargs)

    if kind in ("parallel", "sequential"):
        rules: list[Rule] = []
        for inner in reversed(rule.rules):  # type: ignore[union-attr]
            r = _reverse_rule(inner)
            if r is not None:
                rules.append(r)
        if kind == "parallel":
            return ParallelRule(rules=tuple(rules))
        return SequentialRule(rules=tuple(rules))

    raise MapLogicError(f"unknown rule kind: {kind!r}")  # pragma: no cover


def _reverse_sub(rule: SubRule) -> SubRule | None:
    """`Interscript::Node::Rule::Sub#reverse`. Returns ``None`` when the
    reversed rule must not execute: a rule whose reversed ``from`` is
    empty (and carries no assertions) would match EVERYWHERE — ruby's
    Sub#reverse marks those reverse_run: true so the executor skips
    them, and the compiled-IR equivalent is absence."""
    if rule.from_ is None:
        raise MapLogicError("sub rule missing 'from'")

    to = rule.to
    if isinstance(to, FuncallInline):
        # `sub from, to upcase` reverses to `sub from.downcase,
        # to downcase` (Item#downcase / Item#upcase parity, and vice versa).
        if to.name == "upcase":
            xfrom = _item_case(rule.from_, False)
            xto: Item | FuncallInline = FuncallInline(name="downcase")
        elif to.name == "downcase":
            xfrom = _item_case(rule.from_, True)
            xto = FuncallInline(name="upcase")
        else:
            # rs builder: only upcase/downcase functions become SubTo
            # targets; any other inline funcall walks the transfer and
            # hits its unhandled arm.
            xfrom, xto = _reverse_transfer(rule.from_, to)
    else:
        xfrom, xto = _reverse_transfer(rule.from_, to if to is not None else EMPTY_STRING)

    has_assertions = any(
        v is not None for v in (rule.before, rule.not_before, rule.after, rule.not_after)
    )
    if has_assertions or not _is_empty_from(xfrom):
        return SubRule(
            from_=xfrom,
            to=xto,
            # Constraints pass through UNCHANGED (ruby keeps
            # before/after/not_before/not_after as-is); `priority`
            # negates (ruby Sub#reverse); `when` guards carry over
            # unchanged (ISC-WF-1 W3 — the language selection filters
            # the same rows on either surface).
            before=rule.before,
            not_before=rule.not_before,
            after=rule.after,
            not_after=rule.not_after,
            priority=-rule.priority if rule.priority is not None else None,
            when=rule.when,
            kind="sub",
        )
    return None


def _is_empty_from(item: Item) -> bool:
    """The ruby empty-from test: ``xfrom == "" || String("")`` (plus
    ruby's ``Alias(:none)`` arm, unreachable in the compiled IR — the
    converter lowers ``none`` to an empty string item)."""
    return isinstance(item, StringItem) and item.value == ""


# ---------------------------------------------------------------------------
# Item#downcase / Item#upcase (Sub#reverse to upcase/downcase case)
# ---------------------------------------------------------------------------


def item_downcase(item: Item) -> Item:
    """`Item#downcase`."""
    return _item_case(item, False)


def item_upcase(item: Item) -> Item:
    """`Item#upcase`."""
    return _item_case(item, True)


def _item_case(item: Item, up: bool) -> Item:
    """`Item#downcase`/`Item#upcase`: string data case-maps; groups and
    captures recurse; aliases (incl. boundary prims) and refs are
    identity; `any` rebuilds from per-entry case-mapped children; a
    char-class range rebuilds as the set of its per-char entries
    (``Any.new(data.map(&:downcase))`` parity)."""

    def apply(s: str) -> str:
        return s.upper() if up else s.lower()

    kind = item.kind
    if kind == "string":
        assert isinstance(item, StringItem)
        return StringItem(value=apply(item.value))
    if kind in ("alias", "capture_ref"):
        # Item::Alias#downcase/#upcase = self; refs too.
        return item
    if kind == "capture_group":
        assert isinstance(item, CaptureGroupItem)
        return CaptureGroupItem(data=_item_case(item.data, up))
    if kind == "group":
        assert isinstance(item, GroupItem)
        return GroupItem(items=tuple(_item_case(c, up) for c in item.items))
    if kind == "any":
        assert isinstance(item, AnyItem)
        return AnyItem(of=tuple(_item_case(c, up) for c in item.of))
    if kind == "any_char_class":
        assert isinstance(item, AnyCharClassItem)
        if item.range is not None:
            lo, hi = item.range
            entries: list[Item] = []
            cp = ord(lo)
            while True:
                entries.append(StringItem(value=apply(chr(cp))))
                if cp == ord(hi):
                    break
                cp += 1
                if 0xD800 <= cp <= 0xDFFF:
                    # surrogate gap — rs char::from_u32 breaks here too
                    break
            return AnyItem(of=tuple(entries))
        if item.chars is not None:
            return AnyItem(of=tuple(StringItem(value=apply(c)) for c in item.chars))
        return item
    if kind == "repeat":
        # Ruby Item::Repeat has no downcase/upcase: NoMethodError.
        raise MapLogicError(
            "repeat item in a to-upcase/downcase sub (the Ruby reverse raises NoMethodError)"
        )
    raise MapLogicError(
        f"unhandled item kind {kind!r} in a to-upcase/downcase sub "
        "(the Ruby reverse raises NoMethodError)"
    )


# ---------------------------------------------------------------------------
# Sub#reverse_transfer: boundary hoisting + capture/ref exchange
# ---------------------------------------------------------------------------


def _is_boundary_like(item: Item) -> bool:
    return item.kind == "alias" and item.name in BOUNDARY_LIKE_ALIASES  # type: ignore[union-attr]


def _compact_items(children: list[Item]) -> Item:
    """Ruby ``Group#compact`` over an already-collected children list:
    drop none/"" children; 0 -> none (the IR empty string), 1 -> the
    child."""
    kept = [c for c in children if not (c.kind == "string" and c.value == "")]  # type: ignore[union-attr]
    if not kept:
        return StringItem(value="")
    if len(kept) == 1:
        return kept[0]
    return GroupItem(items=tuple(kept))


def _group_plus_compact(prefix: list[Item], last: Item) -> Item:
    """Ruby ``Group.new + a + b ...`` then ``compact``: a fresh group
    whose children are the leading items plus ``last`` — flattened when
    ``last`` is itself a group (``Group#+`` merges children)."""
    children = list(prefix)
    if last.kind == "group":
        children.extend(last.items)  # type: ignore[union-attr]
    else:
        children.append(last)
    return _compact_items(children)


def _reverse_transfer(from_: Item, to: Item | FuncallInline) -> tuple[Item, Item]:
    """`Interscript::Node::Rule::Sub#reverse_transfer`: boundary-like
    aliases at the from edges move onto the to side; then the
    capture/ref exchange runs. Returns (reversed_from, reversed_to) —
    the ruby multi-assign ``xto, xfrom = reverse_transfer(from, to)``
    swaps the results."""
    f: Item | FuncallInline = from_
    t: Item | FuncallInline = to

    if isinstance(f, GroupItem):
        # Ruby reads first/last BEFORE either mutation.
        parts = f.items
        first = parts[0] if parts else None
        last = parts[-1] if parts else None

        # first child boundary-like -> prepended to `to`
        if first is not None and _is_boundary_like(first):
            t = _group_plus_compact([first], t)  # type: ignore[arg-type]
            f = _compact_items(list(parts[1:]))
        # last child boundary-like -> appended to `to`. Ruby mutates
        # `from.children` here, which requires `from` to still be a
        # Group; a first-hoist that consumed the whole group crashes
        # there (NoMethodError).
        if last is not None and _is_boundary_like(last):
            if not isinstance(f, GroupItem):
                raise MapLogicError(
                    "boundary hoist consumed the whole from group "
                    "(the Ruby reverse raises NoMethodError)"
                )
            shorter = list(f.items[:-1])
            t = _group_plus_compact([t], last)  # type: ignore[arg-type]
            f = _compact_items(shorter)
    elif _is_boundary_like(f):
        # Whole-from boundary alias: `_end`-suffixed names append after
        # `to`, everything else prepends before it; from becomes `none`.
        # Ruby tests `from.name.end_with?("_end")` — among the ISC prims
        # only line_end qualifies (string_end is not in the grammar).
        boundary = f
        if boundary.kind == "alias" and boundary.name == "line_end":  # type: ignore[union-attr]
            t = _group_plus_compact([t], boundary)  # type: ignore[arg-type]
        else:
            t = _group_plus_compact([boundary], t)  # type: ignore[arg-type]
        f = StringItem(value="")

    # --- capture/ref exchange ---
    state = _TransferState()
    visited_from = _transfer_visit(f, "from", state)
    visited_to = _transfer_visit(t, "to", state)
    # xto, xfrom = reverse_transfer(from, to)
    return visited_to, visited_from


class _TransferState:
    """Ruby ``state[:left]`` (every capture group seen, in visit order;
    minted ref ids index into it, 1-based) and ``state[:right]`` (ref
    ids already substituted on the `to` side — a second occurrence
    stays a literal ref)."""

    def __init__(self) -> None:
        self.left: list[Item | FuncallInline] = []
        self.right: set[int] = set()


def _transfer_visit(node: Item | FuncallInline, side: str, state: _TransferState) -> Item:
    """``reverse_transfer_visit``. Refs stay positional numbers — the
    regex engine numbers the reversed rule's groups in regex order at
    compile time, the same numbers ruby's ``build_regexp`` assigns at
    build time."""
    kind = node.kind

    if kind == "alias":
        # Alias :kor_maybedash -> CaptureRef(left.length). (rs's
        # builder expands the alias to its capture(maybe("-")) tree
        # before reverse sees it, where the CaptureGroup branch handles
        # it with identical numbering — this branch guards direct alias
        # items and documents the Ruby special case.)
        if node.name == "kor_maybedash":  # type: ignore[union-attr]
            state.left.append(node)
            return CaptureRefItem(id=len(state.left))
        return node  # type: ignore[return-value]

    if kind == "string":
        return node  # type: ignore[return-value]

    if kind == "capture_ref":
        if side == "from":
            return node  # type: ignore[return-value]
        # refs on the to side: the first occurrence substitutes the
        # matching from-side group; further occurrences stay refs.
        assert isinstance(node, CaptureRefItem)
        if node.id in state.right:
            return node
        state.right.add(node.id)
        if node.id - 1 >= len(state.left):
            raise MapLogicError("Capture count doesn't match")
        return state.left[node.id - 1]  # type: ignore[return-value]

    if kind == "capture_group":
        assert isinstance(node, CaptureGroupItem)
        state.left.append(node)
        out: Item = CaptureRefItem(id=len(state.left))
        _transfer_visit(node.data, side, state)  # visit but don't care
        return out

    if kind == "any":
        assert isinstance(node, AnyItem)
        return AnyItem(of=tuple(_transfer_visit(c, side, state) for c in node.of))

    if kind == "group":
        assert isinstance(node, GroupItem)
        return GroupItem(items=tuple(_transfer_visit(c, side, state) for c in node.items))

    if kind == "repeat":
        # Repeat: only the data is visited; the repeat kind survives.
        assert isinstance(node, RepeatItem)
        return replace(node, item=_transfer_visit(node.item, side, state))

    if kind == "any_char_class":
        return node  # type: ignore[return-value]

    raise MapLogicError(
        f"Type {kind} unhandled in reverse_transfer_visit "
        '(the Ruby raises "Type ... unhandled!")'
    )
