# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""ISC parser — public entry + document model + W1/W2 expansion.

Parsing is GENERATED FROM THE GRAMMAR: the canonical `.parg` text
(vendored in `grammar/grammar_source.py`, sha256-pinned, synced from
interscript-ruby's lib/interscript/isc/grammar/isc.parg) is compiled by
a PARG reader (`grammar/parg_reader.py`), executed by a table-driven
PEG interpreter reproducing parsanol's capture/flattening semantics
(`grammar/peg.py`), and lowered to an IscDocument by the action layer
(`grammar/actions.py`) — mirroring interscript-ts's WO17 step-4b
generated parser. `parse_isc` keeps its public signature:

    doc = parse_isc(source, "map.isc")
    doc = parse_isc(source, resolve_dependency=lambda code: other_doc)
    cm = isc_to_compiled_map(doc)   # -> executor.execute_stage(cm, ...)

This module keeps what is NOT generated from the grammar — the ISC-WF-1
document model and its runtime semantics (the ts runtime's
src/isc/types.ts + expand.ts equivalent):

- **W1 named rulesets** — `ruleset <ident> { ... }` at map top level.
- **W2 use with override** — `use <ident> [override { <sub rules> }]`,
  expanded at parse time: a macro splice of the referenced ruleset's
  items at the use position (recursive; cycles are a parse error),
  with child-wins row overrides on exact from-equality (spec §4.2).
- **W3 language conditioning** — `languages <ident>...` inside the
  system block and the `when <ident>...` guard suffix on `sub` rules.
  Guards are carried into the IR (`CompiledMap.languages`,
  `SubRule.when`) and resolved at RUN time by the executor (§5).

W1/W2 therefore never reach the executor: expanded maps compile to the
same IR shapes as before, plus the two optional W3 fields. The parser
emits `_ir_types` structures directly, so the parse path and the
JSON-IR loader share one runtime representation.

Parser fidelity notes:

- The generated parser reproduces the former hand parser's documents
  byte-for-byte across the whole maps corpus (434/434 through the
  py-vs-py parity driver, scripts/parse_parity_py.py), including the
  §4.2.6 trailing-parallel override join and byte-exact `from_source`
  override keys. Documented hand-parser quirks the grammar rejects
  (invalid `\\u` escapes, hyphenated identifiers outside run targets,
  multi-digit capture refs, stage-level reverse/strip/swapcase) are
  corpus-dormant; see grammar/actions.py for the full deviation list.
- `languages` is declared once per map; a second declaration is a parse
  error. `use` may appear in stage bodies, ruleset bodies and inside
  `parallel`/`sequence` blocks (WO18 G5, spec §3.2): inside a pass block
  the expansion flattens the referenced ruleset's rules into the
  enclosing collection, and a referenced ruleset carrying non-rule
  items (funcalls/stage runs) is a named load error.

Performance note (measured, same machine): the generated parser parses
the full 434-file corpus in ~86s where the hand parser took ~7s — the
interpreter spends its time in the same table-driven way the ts
generated parser does, and python function-call costs dominate. Typical
maps (5-50KB) parse in tens of milliseconds; the gap only shows on the
megabyte jamo/hanja maps, in the golden/embedded gates that parse the
whole corpus. Follow-ups (closure compilation, grammar-specific
prefilters) can close the gap without touching semantics; parity, not
speed, was this milestone's gate.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from ._ir_types import (
    AliasItem,
    CompiledMap,
    FuncallInline,
    FuncallRule,
    ParallelRule,
    RunRule,
    SequentialRule,
    Stage,
    SubRule,
)
from .errors import IscParseError, MapFormatError

DependencyResolver = Callable[[str], "IscDocument | None"]


# ---------------------------------------------------------------------------
# Parse-level document types (mirror interscript-ts src/isc/types.ts)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class IscTest:
    input: str
    expected: str
    note: str | None = None


@dataclass(frozen=True)
class IscDependency:
    target: str
    alias_name: str | None = None


@dataclass(frozen=True)
class IscStage:
    """One stage; `items` are expanded parse-level items (no `use`)."""

    name: str
    items: tuple[Any, ...]


@dataclass(frozen=True)
class IscDocument:
    system_code: str
    metadata: dict[str, Any]
    tests: tuple[IscTest, ...]
    aliases: tuple[tuple[str, Any], ...]
    stages: tuple[IscStage, ...]
    dependencies: tuple[IscDependency, ...]
    languages: tuple[str, ...] | None
    rulesets: dict[str, tuple[Any, ...]]


# ---------------------------------------------------------------------------
# Parse-level stage items
#
# Rules carry their IR form plus the raw source text of the `from` atom,
# which is the W2 override key (byte-exact string equality, §4.2).
# Blocks hold rules until isc_to_compiled_map lowers them to IR.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ParsedRule:
    rule: SubRule
    from_source: str | None = None


@dataclass(frozen=True)
class ParallelBlock:
    rules: tuple[Any, ...]


@dataclass(frozen=True)
class SequenceBlock:
    rules: tuple[Any, ...]


@dataclass(frozen=True)
class RunItem:
    dependency: str | None
    stage: str


@dataclass(frozen=True)
class RawUse:
    """Unexpanded `use` directive (resolved in the post-parse pass)."""

    name: str
    dependency_alias: str | None = None
    override: tuple[ParsedRule, ...] | None = None


# ---------------------------------------------------------------------------
# W1/W2 expansion (unchanged from the replaced hand parser's _Parser;
# the generated action layer drives it after the capture tree is built)
# ---------------------------------------------------------------------------


class _Expander:
    """Expands ruleset `use` directives (W1) and applies override rows
    (W2, §4.2 + §4.2.6) over an already-parsed raw map body."""

    def __init__(
        self,
        system_code: str,
        dependencies: list[IscDependency],
        resolve_dependency: DependencyResolver | None,
        src: str,
        filename: str | None,
        raw_rulesets: dict[str, list[Any]],
    ) -> None:
        self._system_code = system_code
        self._dependencies = dependencies
        self.resolve_dependency = resolve_dependency
        self._src = src
        self._filename = filename
        # Raw (unexpanded) ruleset bodies, from the parsed tree.
        self._raw_rulesets = raw_rulesets
        # Memo of fully expanded rulesets (this map only; dependency
        # rulesets arrive already expanded in their own IscDocument).
        self.expanded: dict[str, list[Any]] = {}

    def error(self, msg: str) -> None:
        pos = len(self._src)
        line = self._src[:pos].count("\n") + 1
        col = pos - self._src.rfind("\n", 0, pos)
        full_msg = f"{self._filename}: {msg}" if self._filename else msg
        raise IscParseError(full_msg, pos, line, col)

    def expand_ruleset(self, name: str, chain: tuple[tuple[str, str], ...] = ()) -> list[Any]:
        entry = (self._system_code, name)
        if entry in chain:
            self.error(f"use cycle: {' -> '.join(f'{m}/{r}' for m, r in (*chain, entry))}")
        cached = self.expanded.get(name)
        if cached is not None:
            return cached
        raw = self._raw_rulesets.get(name)
        if raw is None:
            self.error(f"unknown ruleset: {name}")
        expanded = self.expand_items(raw, chain + (entry,), False)
        self.expanded[name] = expanded
        return expanded

    def expand_items(
        self, items: list[Any], chain: tuple[tuple[str, str], ...], in_block: bool
    ) -> list[Any]:
        out: list[Any] = []
        for it in items:
            if isinstance(it, RawUse):
                out.extend(self.expand_use(it, chain, in_block))
                continue
            if isinstance(it, (ParallelBlock, SequenceBlock)):
                it = type(it)(rules=tuple(self.expand_items(list(it.rules), chain, True)))
            out.append(it)
        return out

    def expand_use(
        self, use: RawUse, chain: tuple[tuple[str, str], ...], in_block: bool
    ) -> list[Any]:
        if use.dependency_alias is not None:
            expanded = self.expand_via_dependency(use, chain)
        else:
            expanded = self.expand_ruleset(use.name, chain)

        if in_block:
            # WO18 G5 — spec §3.2: items inside a parallel/sequence block
            # participate in that block's single pass; the expansion
            # inherits the enclosing pass structure — the target's rule
            # content flattens into the enclosing collection (interscript-rs
            # resolve_use_rules). Overrides merge per-rule on the flat list.
            rules = self._flatten_pass_items(expanded, chain)
            if use.override is not None:
                rules = self._merge_override_rules(
                    rules, self._expand_override_rows(use.override, chain)
                )
            return rules

        if use.override is not None:
            expanded = self._apply_override(expanded, list(use.override))
        return list(expanded)

    def _flatten_pass_items(
        self, items: list[Any], chain: tuple[tuple[str, str], ...]
    ) -> list[Any]:
        """WO18 G5: flatten a structural expansion into the ordered rule
        list of an enclosing pass (§3.2). Pass blocks contribute their
        (already-expanded) rules in position; raw uses inside them were
        flattened during expand_items. Non-rule items (funcalls, stage
        runs) cannot join a pass — named load error."""
        out: list[Any] = []
        for it in items:
            if isinstance(it, (ParallelBlock, SequenceBlock)):
                out.extend(it.rules)
            elif isinstance(it, ParsedRule):
                out.append(it)
            elif isinstance(it, RawUse):
                out.extend(self.expand_use(it, chain, True))
            else:
                self.error(
                    "use inside a parallel/sequence block: the referenced ruleset "
                    "carries non-rule items (funcalls/stage runs) that cannot join "
                    "the pass"
                )
        return out

    def _expand_override_rows(
        self, rows: tuple[ParsedRule, ...], chain: tuple[tuple[str, str], ...]
    ) -> list[ParsedRule]:
        """WO18 G5: an override block is a rule_line list, so its rows may
        themselves be `use` directives (rs extract_rule_list recursion);
        their content flattens into the override row list."""
        out: list[ParsedRule] = []
        for row in rows:
            if isinstance(row, RawUse):
                out.extend(self.expand_use(row, chain, True))
            else:
                out.append(row)
        return out

    def _merge_override_rules(
        self, rules: list[Any], overrides: list[ParsedRule]
    ) -> list[Any]:
        """§4.2 child-wins merge over a FLAT rule list (the block-position
        use): matching rules drop wherever they sit; the override rows land
        at the expansion tail. No trailing-parallel join here — the caller
        re-wraps the list into the enclosing block's structure."""
        o_keys = {self._from_key(o) for o in overrides}
        kept = [r for r in rules if self._from_key(r) not in o_keys]
        return kept + list(overrides)

    def expand_via_dependency(
        self, use: RawUse, chain: tuple[tuple[str, str], ...]
    ) -> list[Any]:
        target = next(
            (
                d.target
                for d in self._dependencies
                if d.alias_name == use.dependency_alias
            ),
            None,
        )
        if target is None:
            self.error(f"unknown dependency alias: {use.dependency_alias}")
        if self.resolve_dependency is None:
            self.error(
                f"cannot resolve dependency {target!r} for use "
                f"{use.dependency_alias}.{use.name} (no resolver provided)"
            )
        dep_doc = self.resolve_dependency(target)
        if dep_doc is None:
            self.error(f"cannot resolve dependency: {target}")
        entry = (dep_doc.system_code, use.name)
        if entry in chain:
            self.error(f"use cycle: {' -> '.join(f'{m}/{r}' for m, r in (*chain, entry))}")
        expanded = dep_doc.rulesets.get(use.name)
        if expanded is None:
            self.error(f"unknown ruleset in dependency {target!r}: {use.name}")
        return list(expanded)

    @staticmethod
    def _from_key(rule: ParsedRule) -> Any:
        """The W2 override key: the byte-exact source text of the `from`
        atom (spec §4.2); falls back to the IR item's structural equality
        for rules built programmatically (no source span)."""
        return rule.from_source if rule.from_source is not None else rule.rule.from_

    def _apply_override(
        self, items: list[Any], overrides: list[ParsedRule]
    ) -> list[Any]:
        """ISC-WF-1 §4.2 + §4.2.6 merge: partition R by byte-exact
        from-equality (ALL same-from rules replaced), then place O —
        when the expansion ends with a parallel block, ALL of O joins
        that block (replacements and additions share one longest-match
        pass, §4.2.5/§4.2.6); otherwise O appends after R_kept as
        stage-level rows. Cross-grammar canonical: the ruby reference
        and the ts runtime both join the trailing parallel (found by
        maps scripts/parse-parity.mjs — pre-parity py appended unmatched
        additions as bare stage rules, splitting the pass)."""
        okeys = [self._from_key(o) for o in overrides]
        out: list[Any] = []
        for it in items:
            if isinstance(it, ParsedRule):
                if self._from_key(it) in okeys:
                    continue
                out.append(it)
            elif isinstance(it, (ParallelBlock, SequenceBlock)):
                kept = tuple(
                    r
                    for r in it.rules
                    if not (isinstance(r, ParsedRule) and self._from_key(r) in okeys)
                )
                out.append(type(it)(rules=kept))
            else:
                out.append(it)
        tail = out[-1] if out else None
        if isinstance(tail, ParallelBlock):
            out[-1] = ParallelBlock(rules=tuple(tail.rules) + tuple(overrides))
            return out
        out.extend(overrides)
        return out


# ---------------------------------------------------------------------------
# Public parse entry — generated parser (grammar/)
# ---------------------------------------------------------------------------


def parse_isc(
    source: str,
    filename: str | None = None,
    resolve_dependency: DependencyResolver | None = None,
) -> IscDocument:
    """Parse one .isc source into an expanded IscDocument.

    `resolve_dependency` maps a dependency's target system code to its
    parsed IscDocument; it is called lazily when a `use alias.<ident>`
    expansion needs the dependency's rulesets. W1 `use` splicing and W2
    override merging happen here, at parse time.
    """
    from .grammar.isc_parser import parse_isc as _generated_parse

    return _generated_parse(source, filename, resolve_dependency)


# ---------------------------------------------------------------------------
# Rule assembly + converter (mirror interscript-ts src/isc/converter.ts)
# ---------------------------------------------------------------------------


def _function_to_inline(item: Any, kind: str) -> Any:
    """Lower a function atom in `to` position to a FuncallInline."""
    if kind == "function" and isinstance(item, AliasItem):
        return FuncallInline(name=item.name)
    return item


def _make_sub_rule(
    from_: Any,
    to: Any,
    constraints: list[tuple[str, Any]],
    when: tuple[str, ...] | None,
) -> SubRule:
    picked = {kind: item for kind, item in constraints}
    return SubRule(
        from_=from_,
        to=to,
        before=picked.get("before"),
        after=picked.get("after"),
        not_before=picked.get("not_before"),
        not_after=picked.get("not_after"),
        when=when,
    )


def isc_to_compiled_map(doc: IscDocument) -> CompiledMap:
    """Lower an expanded IscDocument to the compiled JSON-IR `CompiledMap`
    consumed by the executor (port of `iscToCompiledMap`)."""
    aliases = {name: item for name, item in doc.aliases}
    dep_aliases = {d.alias_name: d.target for d in doc.dependencies if d.alias_name}
    stages = tuple(
        Stage(
            name=s.name,
            rules=tuple(_lower_item(it, dep_aliases) for it in s.items),
        )
        for s in doc.stages
    )
    return CompiledMap(
        schema_version=1,
        system_code=doc.system_code,
        dependencies=tuple(d.target for d in doc.dependencies),
        stages=stages,
        aliases=aliases,
        functions={},
        metadata=dict(doc.metadata) if doc.metadata else None,
        languages=doc.languages,
    )


def _lower_item(item: Any, dep_aliases: dict[str, str]) -> Any:
    if isinstance(item, ParallelBlock):
        return ParallelRule(rules=tuple(_lower_rule(r) for r in item.rules))
    if isinstance(item, SequenceBlock):
        return SequentialRule(rules=tuple(_lower_rule(r) for r in item.rules))
    if isinstance(item, ParsedRule):
        return _lower_rule(item)
    if isinstance(item, RunItem):
        doc_name = dep_aliases.get(item.dependency, item.dependency) if item.dependency else None
        return RunRule(stage=item.stage, doc_name=doc_name)
    if isinstance(item, FuncallRule):
        return item
    raise MapFormatError(f"unrecognized parse-level stage item: {type(item).__name__}")


def _lower_rule(rule: ParsedRule) -> SubRule:
    return rule.rule


# Re-export for callers that want the error without reaching into errors.
__all__ = [
    "IscDependency",
    "IscDocument",
    "IscParseError",
    "IscStage",
    "IscTest",
    "ParallelBlock",
    "ParsedRule",
    "RawUse",
    "RunItem",
    "SequenceBlock",
    "isc_to_compiled_map",
    "parse_isc",
]
