# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Item compilation — convert IR Items into regex source or literal text.

Port of interscript-ts's `src/runtime/compile-item.ts`, which mirrors
Ruby's `Node::Item` compilation. Adding a new Item kind = adding a case
to each dispatcher here (OCP: existing cases never change).
"""

from __future__ import annotations

from dataclasses import dataclass

from ._ir_types import (
    AliasItem,
    AnyCharClassItem,
    AnyItem,
    CaptureGroupItem,
    CaptureRefItem,
    GroupItem,
    Item,
    RepeatItem,
    StringItem,
)
from .context import ExecutionContext
from .errors import MapLogicError
from .stdlib import regexp_escape


@dataclass(frozen=True)
class CompiledItem:
    """Regex source + literal form of a pattern Item."""

    re: str
    literal: str


@dataclass(frozen=True)
class _StdlibAlias:
    re: str
    literal: str


def _compiled(re_src: str, literal: str) -> CompiledItem:
    return CompiledItem(re=re_src, literal=literal)


def _alias_compiled(name: str) -> _StdlibAlias:
    return _StdlibAlias(re=ALIAS_COMPILED[name].re, literal=ALIAS_COMPILED[name].literal)


def compile_item(item: Item, ctx: ExecutionContext) -> CompiledItem:
    """Compile an Item into regex source + literal replacement text."""
    kind = item.kind
    if kind == "string":
        assert isinstance(item, StringItem)
        return _compiled(regexp_escape(item.value), item.value)
    if kind == "capture_group":
        assert isinstance(item, CaptureGroupItem)
        inner = compile_item(item.data, ctx)
        return _compiled(f"({inner.re})", inner.literal)
    if kind == "capture_ref":
        assert isinstance(item, CaptureRefItem)
        return _compiled("\\" + str(item.id), f"${item.id}")
    if kind == "alias":
        assert isinstance(item, AliasItem)
        if item.name in ALIAS_COMPILED:
            a = _alias_compiled(item.name)
            return _compiled(a.re, a.literal)
        resolved = ctx.resolve_alias(item.name)
        if resolved is None:
            return _compiled("", "")
        return compile_item(resolved, ctx)
    if kind == "any":
        assert isinstance(item, AnyItem)
        parts = [compile_item(child, ctx).re for child in item.of]
        # Mirror Ruby's Any#nth_string: the literal form picks the first
        # alternative (sub rules with `to: any("ie")` use it as the
        # canonical replacement).
        first = compile_item(item.of[0], ctx).literal if item.of else ""
        return _compiled("(?:" + "|".join(parts) + ")", first)
    if kind == "any_char_class":
        assert isinstance(item, AnyCharClassItem)
        if item.range:
            first, last = item.range
            return _compiled(
                f"[{regexp_escape(first)}-{regexp_escape(last)}]",
                first,
            )
        if item.chars:
            escaped = "".join(regexp_escape(c) for c in item.chars)
            return _compiled(f"[{escaped}]", item.chars[0])
        return _compiled("[^]", "")
    if kind == "group":
        assert isinstance(item, GroupItem)
        compiled = [compile_item(child, ctx) for child in item.items]
        return _compiled(
            "(?:" + "".join(c.re for c in compiled) + ")",
            "".join(c.literal for c in compiled),
        )
    if kind == "repeat":
        assert isinstance(item, RepeatItem)
        inner = compile_item(item.item, ctx).re
        if item.max is None:
            quant = "*" if item.min == 0 else "+"
        else:
            quant = f"{{{item.min},{item.max}}}"
        return _compiled(f"(?:{inner}){quant}", "")
    if kind == "stage_ref":
        # Stage references are handled by the executor, not by item
        # compilation.
        return _compiled("", "")
    raise MapLogicError(f"unknown item kind: {kind!r}")


def compile_to_literal(item: Item, ctx: ExecutionContext) -> str | None:
    """Compile an Item to a literal string only; `None` when the Item has
    no single literal form (captures, regex-only constructs)."""
    kind = item.kind
    if kind == "string":
        assert isinstance(item, StringItem)
        return item.value
    if kind == "alias":
        assert isinstance(item, AliasItem)
        if item.name in ALIAS_COMPILED:
            return None if ALIAS_COMPILED[item.name].literal == "" else ALIAS_COMPILED[item.name].literal
        resolved = ctx.resolve_alias(item.name)
        if resolved is None:
            return None
        return compile_to_literal(resolved, ctx)
    if kind in ("capture_group", "capture_ref", "repeat", "stage_ref"):
        return None
    if kind == "any_char_class":
        assert isinstance(item, AnyCharClassItem)
        # Mirror Ruby's Any#nth_string: first char of the class.
        if item.chars:
            return item.chars[0]
        if item.range:
            return item.range[0]
        return None
    if kind == "any":
        assert isinstance(item, AnyItem)
        if not item.of:
            return None
        return compile_to_literal(item.of[0], ctx)
    if kind == "group":
        assert isinstance(item, GroupItem)
        out = ""
        for child in item.items:
            lit = compile_to_literal(child, ctx)
            if lit is None:
                return None
            out += lit
        return out
    return None


def expand_from_literals(item: Item, ctx: ExecutionContext) -> list[str] | None:
    """Expand a `from` item into ALL possible literal strings for the
    trie-based parallel replace. `any` items produce one entry per
    alternative; `None` when not literal-representable."""
    kind = item.kind
    if kind == "string":
        assert isinstance(item, StringItem)
        return [item.value]
    if kind == "alias":
        assert isinstance(item, AliasItem)
        if item.name in ALIAS_COMPILED:
            return None
        resolved = ctx.resolve_alias(item.name)
        if resolved is None:
            return None
        return expand_from_literals(resolved, ctx)
    if kind == "any_char_class":
        assert isinstance(item, AnyCharClassItem)
        # One entry per char (ranges expand every code point) — mirrors
        # Ruby's parallel-tree expansion.
        if item.chars:
            return list(item.chars)
        if item.range:
            first, last = item.range
            return [chr(cp) for cp in range(ord(first), ord(last) + 1)]
        return None
    if kind == "any":
        assert isinstance(item, AnyItem)
        out: list[str] = []
        for child in item.of:
            lits = expand_from_literals(child, ctx)
            if lits is None:
                return None
            out.extend(lits)
        return out
    if kind == "group":
        assert isinstance(item, GroupItem)
        combos: list[str] = [""]
        for child in item.items:
            alts = expand_from_literals(child, ctx)
            if alts is None:
                return None
            combos = [prefix + suffix for prefix in combos for suffix in alts]
        return combos
    return None


def max_length_of_item(item: Item, ctx: ExecutionContext) -> int:
    """Max-length estimate used only to sort parallel rules longest-first
    (mirrors Ruby's `Node::Item#max_length`; stdlib aliases count 1,
    `none` counts 0)."""
    kind = item.kind
    if kind == "string":
        assert isinstance(item, StringItem)
        return len(item.value)
    if kind == "capture_group":
        assert isinstance(item, CaptureGroupItem)
        return max_length_of_item(item.data, ctx)
    if kind == "capture_ref":
        return 1
    if kind == "alias":
        assert isinstance(item, AliasItem)
        if item.name == "none":
            return 0
        if item.name in ALIAS_COMPILED:
            return 1
        resolved = ctx.resolve_alias(item.name)
        return max_length_of_item(resolved, ctx) if resolved else 1
    if kind == "any":
        assert isinstance(item, AnyItem)
        return max((max_length_of_item(child, ctx) for child in item.of), default=0)
    if kind == "any_char_class":
        return 1
    if kind == "group":
        assert isinstance(item, GroupItem)
        return sum(max_length_of_item(child, ctx) for child in item.items)
    if kind == "repeat":
        assert isinstance(item, RepeatItem)
        return max_length_of_item(item.item, ctx)
    if kind == "stage_ref":
        return 1
    return 1


# ---------------------------------------------------------------------------
# Stdlib alias table (Interscript::Stdlib::ALIASES)
# ---------------------------------------------------------------------------

_BOUNDARY_RE = (
    "(?:(?<![\\p{L}\\p{M}])(?=[\\p{L}\\p{M}])|(?<=[\\p{L}\\p{M}])(?![\\p{L}\\p{M}]))"
)
_NON_WORD_BOUNDARY_RE = (
    "(?:(?<=[\\p{L}\\p{M}])(?=[\\p{L}\\p{M}])|(?<![\\p{L}\\p{M}])(?![\\p{L}\\p{M}]))"
)

ALIAS_COMPILED: dict[str, _StdlibAlias] = {
    "any_character": _StdlibAlias(re=".", literal=""),
    "none": _StdlibAlias(re="", literal=""),
    "space": _StdlibAlias(re=" ", literal=" "),
    "whitespace": _StdlibAlias(re="\\s+", literal=" "),
    # Unicode-aware word boundaries so Cyrillic, Arabic, Devanagari etc.
    # get correct boundaries (891 alias references across the corpus).
    # Ruby's default \b is ASCII-only; the TS runtime uses the Unicode
    # form and so do we.
    "boundary": _StdlibAlias(re=_BOUNDARY_RE, literal=""),
    "non_word_boundary": _StdlibAlias(re=_NON_WORD_BOUNDARY_RE, literal=""),
    # word / not_word mirror Ruby's default ASCII-only \w / \W on purpose.
    "word": _StdlibAlias(re="[A-Za-z0-9_]", literal=""),
    "not_word": _StdlibAlias(re="[^A-Za-z0-9_]", literal=""),
    "alpha": _StdlibAlias(re="[a-zA-Z]", literal=""),
    "not_alpha": _StdlibAlias(re="[^a-zA-Z]", literal=""),
    "digit": _StdlibAlias(re="[0-9]", literal=""),
    "not_digit": _StdlibAlias(re="[^0-9]", literal=""),
    "line_start": _StdlibAlias(re="^", literal=""),
    "line_end": _StdlibAlias(re="(?=\\n|$)", literal=""),
    "string_start": _StdlibAlias(re="^", literal=""),
    "string_end": _StdlibAlias(re="$", literal=""),
}
