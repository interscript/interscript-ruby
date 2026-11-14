# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Action layer — turns the parslet-shaped capture tree produced by the
PEG interpreter (peg.py) into an IscDocument.

Every action mirrors the replaced hand parser's (the former isc.py
_Parser) semantic action for the same construct, so the generated
parser is a drop-in replacement: identical documents for identical
source — including the W1/W2 ruleset expansion, which runs here through
isc._Expander (the same code the hand parser used). Where the hand
parser deviates from the grammar (each case is corpus-proven dormant by
the 434-file py-vs-py parity driver), the deviation is reproduced and
flagged with a DEVIATION comment — grammar fidelity loses to
swap-safety, on purpose, until the owners decide to align the runtimes.

Mirrors interscript-ts's src/isc/grammar/actions.ts, with the py
runtime's document shapes (SubRule fixed constraint fields, FuncallRule
stage items, from_source override keys, parse-time use expansion).
"""

from __future__ import annotations

from typing import Any

from .._ir_types import (
    AliasItem,
    AnyCharClassItem,
    AnyItem,
    CaptureGroupItem,
    CaptureRefItem,
    FuncallRule,
    GroupItem,
    RepeatItem,
    StringItem,
)
from ..isc import (
    IscDependency,
    IscDocument,
    IscStage,
    IscTest,
    ParallelBlock,
    ParsedRule,
    RawUse,
    RunItem,
    SequenceBlock,
    _Expander,
    _function_to_inline,
    _make_sub_rule,
)
from .peg import Slice

Tree = object
Hash = dict


def _hash(v: Tree) -> Hash:
    if not isinstance(v, dict):
        raise TypeError(
            f"grammar/action mismatch: expected a capture hash, got {v!r}"
        )
    return v


def _array(v: Tree) -> list:
    if not isinstance(v, list):
        raise TypeError(f"grammar/action mismatch: expected an array, got {v!r}")
    return v


def _identifier(tree: Tree) -> str:
    """Text of a captured identifier (a merged slice)."""
    v = _hash(tree)["identifier"]
    return v.content if isinstance(v, Slice) else v  # type: ignore[return-value,union-attr]


def _dependency_name(tree: Tree) -> str:
    """A `run map.a-b.stage.x` dependency name: the hyphen extension
    captures `identifier *("-" identifier)`, so a hyphenated name arrives
    as a list of identifier hashes (the "-" literals are dropped by
    flatten); a plain name is a single hash. Rejoin on "-". (The hand
    parser's identifier scanned hyphens in every identifier slot; the
    corpus is hyphen-free outside run targets.)"""
    if isinstance(tree, list):
        return "-".join(_identifier(t) for t in tree)
    return _identifier(tree)


def _text(v: object) -> str:
    """Text of a captured literal keyword (primitive/function/case names...)."""
    return v.content if isinstance(v, Slice) else v  # type: ignore[return-value,union-attr]


class TreeToDocument:
    def __init__(self, src: str, filename: str | None, resolve_dependency) -> None:
        self._src = src
        self._filename = filename
        self._resolve_dependency = resolve_dependency
        # from/to match spans (peg.py span recording), consumed in tree
        # walk order — one (from, to) pair per compact AND block rule.
        self._spans: list[tuple[str, int, int]] = []
        self._span_ix = 0

    # -- entry --------------------------------------------------------------

    def run(self, tree: Tree, spans: list[tuple[str, int, int]]) -> IscDocument:
        self._spans = spans
        system = _hash(_hash(tree)["system"])
        system_code = self.string(system["system_code"])

        metadata: dict[str, Any] = {}
        tests: list[IscTest] = []
        aliases: list[tuple[str, Any]] = []
        raw_stages: list[tuple[str, list[Any]]] = []
        raw_rulesets: dict[str, list[Any]] = {}
        dependencies: list[IscDependency] = []
        languages: list[str] | None = None

        for entry in _array(system.get("body", [])):
            h = _hash(entry)
            if "metadata" in h:
                metadata.update(self.metadata_fields(_array(h["metadata"])))
                continue
            if "tests" in h:
                tests = [self.test(t) for t in _array(h["tests"])]
                continue
            if "aliases" in h:
                aliases = [
                    (_identifier(ah["name"]), self.item(ah["value"]))
                    for ah in _array(h["aliases"])
                ]
                continue
            if "stage_name" in h and "stage" in h:
                raw_stages.append(
                    (_identifier(h["stage_name"]), self.stage_body(_array(h["stage"])))
                )
                continue
            if "ruleset_name" in h and "ruleset" in h:
                name = _identifier(h["ruleset_name"])
                if name in raw_rulesets:
                    self._error(f"ruleset declared more than once: {name}")
                raw_rulesets[name] = self.stage_body(_array(h["ruleset"]))
                continue
            if "target" in h:
                alias = _identifier(h["alias"]) if "alias" in h else None
                dependencies.append(
                    IscDependency(target=self.string(h["target"]), alias_name=alias)
                )
                continue
            if "languages" in h:
                # Hand parity: `languages` declared more than once is an
                # error; one declaration carries the name list (flatten's
                # fold collapses a single language to a bare hash).
                if languages is not None:
                    self._error("languages declared more than once")
                lv = h["languages"]
                languages = [
                    _identifier(_hash(_hash(l)["language"]))
                    for l in (lv if isinstance(lv, list) else [lv])
                ]
                continue
            raise ValueError(f"unknown system body item {sorted(h.keys())}")

        # W1/W2 expansion (the same code path the hand parser used).
        expander = _Expander(
            system_code,
            dependencies,
            self._resolve_dependency,
            self._src,
            self._filename,
            raw_rulesets,
        )
        for name in raw_rulesets:
            expander.expand_ruleset(name)
        stages = [
            IscStage(name=name, items=tuple(expander.expand_items(items, (), False)))
            for name, items in raw_stages
        ]

        if self._span_ix != len(self._spans):
            raise ValueError(
                f"grammar/action mismatch: {len(self._spans) - self._span_ix} unconsumed "
                f"from/to spans — the tree walk and span recording drifted"
            )

        return IscDocument(
            system_code=system_code,
            metadata=metadata,
            tests=tuple(tests),
            aliases=tuple(aliases),
            stages=tuple(stages),
            dependencies=tuple(dependencies),
            languages=tuple(languages) if languages is not None else None,
            rulesets={name: tuple(expander.expanded[name]) for name in raw_rulesets},
        )

    def _error(self, msg: str) -> None:
        from ..errors import IscParseError

        pos = len(self._src)
        line = self._src.count("\n", 0, pos) + 1
        col = pos - self._src.rfind("\n", 0, pos)
        full = f"{self._filename}: {msg}" if self._filename else msg
        raise IscParseError(full, pos, line, col)

    # -- spans ----------------------------------------------------------------

    def _next_span(self) -> tuple[int, int]:
        """The (start, end) of the next recorded from/to capture."""
        if self._span_ix >= len(self._spans):
            raise ValueError(
                "grammar/action mismatch: no span recorded for a compact rule's "
                "from/to — check peg.py span_names"
            )
        _, start, end = self._spans[self._span_ix]
        self._span_ix += 1
        return start, end

    # -- string literals --------------------------------------------------------

    def string(self, tree: Tree) -> str:
        """Decode a captured string-literal tree ({string: parts-or-slice})."""
        parts = _hash(tree)["string"]
        if not isinstance(parts, list):
            # single-quoted form: the whole body coalesced into one slice
            return parts.content if isinstance(parts, Slice) else parts  # type: ignore[return-value,union-attr]
        out: list[str] = []
        for part in parts:
            h = _hash(part)
            if "run" in h:
                out.append(_text(h["run"]))
            elif "newline" in h:
                out.append("\n")
            elif "carriage_return" in h:
                out.append("\r")
            elif "tab" in h:
                out.append("\t")
            elif "dquote" in h:
                out.append('"')
            elif "backslash" in h:
                out.append("\\")
            elif "u_lone" in h:
                out.append("U")
            elif "unicode" in h:
                digits = _text(h["unicode"])  # type: ignore[arg-type]
                # WO19 G6 ruling: BOTH escape spellings decode. The former
                # hand parser only decoded lowercase \u and rendered a
                # capital \U as a literal "U" followed by the raw digits,
                # so gki-bel's `sub "\U040E" "Ŭ"` carried the from-value
                # "U040E" and the row never fired. The grammar captures
                # both spellings under :unicode and the tree carries the
                # decoded codepoint (ruby/rs always decoded both).
                out.append(chr(int(digits, 16)))
            else:
                raise ValueError(f"unknown string part {sorted(h.keys())}")
        return "".join(out)

    # -- items --------------------------------------------------------------------

    def item(self, tree: Tree, to_position: bool = False) -> Any:
        """A captured `item` — one atom, or a list of atoms (juxtaposition/+).
        Mirrors the hand parser's parse_item: a single atom in `to` position
        lowers a function keyword to a FuncallInline; several atoms form a
        GroupItem."""
        v = _hash(tree)["concatenation"]
        atoms: list[Any] = []
        kinds: list[str] = []
        for a in v if isinstance(v, list) else [v]:
            atom, kind = self.atom(a)
            atoms.append(atom)
            kinds.append(kind)
        if len(atoms) == 1:
            return _function_to_inline(atoms[0], kinds[0]) if to_position else atoms[0]
        return GroupItem(items=tuple(atoms))

    def atom(self, tree: Tree) -> tuple[Any, str]:
        """A single captured `item_atom` -> (IR item, parse kind). Function
        atoms keep their kind so the `to` position can lower them to
        FuncallInline (mirrors the hand parser's parse_item_atom_raw)."""
        h = _hash(tree)
        if "string" in h:
            return StringItem(value=self.string(tree)), "string"
        if "none" in h:
            # converter parity: `none` lowers to the empty string
            return StringItem(value=""), "string"
        if "primitive" in h:
            # DEVIATION (hand-parser parity): py renders primitives as
            # AliasItems (the canonical schema maps them back by name).
            return AliasItem(name=_text(h["primitive"])), "item"
        if "any_char" in h:
            return AliasItem(name="any_character"), "function"
        if "function" in h:
            return AliasItem(name=_text(h["function"])), "function"
        if "any" in h:
            return self.any(_hash(h["any"])), "item"
        if "capture_inner" in h:
            return CaptureGroupItem(data=self.item(h["capture_inner"])), "item"
        if "maybe_inner" in h:
            return RepeatItem(item=self.item(h["maybe_inner"]), min=0, max=1), "item"
        if "some_inner" in h:
            return RepeatItem(item=self.item(h["some_inner"]), min=1, max=None), "item"
        if "ref" in h:
            digit = _hash(h["ref"])["digit"]
            # DEVIATION (grammar fidelity): the grammar pins ref(N) to a
            # single digit; the hand parser's number scanner accepted
            # multi-digit ids. The corpus is single-digit (the executor
            # only addresses capture groups 1-9); dormant.
            return CaptureRefItem(id=int(_text(digit))), "item"
        if "alias" in h:
            a = _hash(h["alias"])
            # DEVIATION (grammar fidelity, ts parity): a qualified alias
            # reference inside items (`a.b`) is accepted by the grammar and
            # spelled with the dot; the hand parser's identifier scan
            # stopped at the dot and rejected the reference. The corpus is
            # dotted-alias-free.
            q = "." + _identifier(a["qualified_name"]) if "qualified_name" in a else ""
            return AliasItem(name=_identifier(a) + q), "item"
        raise ValueError(f"unknown item atom {sorted(h.keys())}")

    def any(self, h: Hash) -> Any:
        if "single" in h:
            # any("abc") — the hand parser splits a plain string into
            # per-character string items.
            v = self.string(h["single"])
            return AnyItem(of=tuple(StringItem(value=c) for c in v))
        if "lo" in h and "hi" in h:
            return AnyCharClassItem(range=(self.string(h["lo"]), self.string(h["hi"])))
        if "list" in h:
            # one list item collapses to a bare concatenation hash
            lv = h["list"]
            return AnyItem(of=tuple(self.item(t) for t in (lv if isinstance(lv, list) else [lv])))
        if "alias_ref" in h:
            item, _ = self.atom({"alias": h["alias_ref"]})
            return AnyItem(of=(item,))
        if "any_item" in h:
            # The DSL's `item` fallback inside any(...) — GRAMMAR_EXTENSIONS
            # any_arg, hand-parser parity (`any(item)`, `any(item + item)`).
            return AnyItem(of=(self.item(h["any_item"]),))
        raise ValueError(f"unknown any() shape {sorted(h.keys())}")

    # -- rules ----------------------------------------------------------------------

    def rule(self, tree: Tree) -> ParsedRule:
        h = _hash(tree)
        constraints: list[tuple[str, Any]] = []
        for c in self.item_list(h.get("constraints")) or []:
            entry = next(iter(_hash(c).items()))
            constraints.append((entry[0], self.item(entry[1])))
        # The hand parser folds constraints into SubRule's four fixed
        # fields, last kind-wins (written order between kinds is lost).
        when_list = self.item_list(h.get("when"))
        when = (
            tuple(_identifier(_hash(_hash(w)["when_lang"])) for w in when_list)
            if when_list is not None
            else None
        )
        # Compact rules capture raw item_atoms (`sub "a" "b"`); block rules
        # capture full items (`from "a"` — a concatenation tree). The
        # concatenation key tells them apart.
        if "concatenation" in _hash(h["from"]):
            from_item = self.item(h["from"])
            self._next_span()  # block rules carry no from_source
            to_item = self.item(h["to"], to_position=True)
            self._next_span()
            from_source = None
        else:
            # Compact: from/to are single atoms; the W2 override key is the
            # byte-exact source text of the from atom (the span peg.py
            # recorded for this capture — identical to the hand parser's
            # src[atom_start:atom_end].strip()).
            from_item, _ = self.atom(h["from"])
            start, end = self._next_span()
            to_item, to_kind = self.atom(h["to"])
            to_item = _function_to_inline(to_item, to_kind)
            self._next_span()
            from_source = self._src[start:end].strip()
        return ParsedRule(
            rule=_make_sub_rule(from_item, to_item, constraints, when),
            from_source=from_source,
        )

    def item_list(self, v: Tree | None) -> list | None:
        """A captured repetition's value: a list, or a single merged hash
        when exactly one iteration produced a capture (flatten's sequence
        fold drops the list wrapper). None when the capture is absent."""
        if v is None:
            return None
        return v if isinstance(v, list) else [v]

    def rule_list(self, trees: list) -> list:
        """rule_items for parallel/sequence blocks: skip comment/noop rows;
        `use` directives splice into the pass (canonical grammar
        rule_line — the expansion resolves them in place, spec §3.2)."""
        out: list[Any] = []
        for t in trees:
            h = _hash(t)
            if "comment" in h or "noop" in h:
                continue
            if "use" in h:
                out.append(self.use_item(_hash(h["use"])))
            else:
                out.append(self.rule(t))
        return out

    # -- stage bodies -------------------------------------------------------------

    def stage_body(self, trees: list) -> list[Any]:
        out: list[Any] = []
        for tree in trees:
            h = _hash(tree)
            if "comment" in h or "noop" in h:
                continue
            if "bare_rule" in h:
                out.append(self.rule(h["bare_rule"]))
                continue
            if "parallel" in h:
                out.append(ParallelBlock(rules=tuple(self.rule_list(_array(h["parallel"])))))
                continue
            if "sequence" in h:
                out.append(SequenceBlock(rules=tuple(self.rule_list(_array(h["sequence"])))))
                continue
            if "dep" in h and "stage" in h:
                out.append(
                    RunItem(dependency=_dependency_name(h["dep"]), stage=_identifier(h["stage"]))
                )
                continue
            if "run_stage_only" in h:
                out.append(RunItem(dependency=None, stage=_identifier(_hash(h["run_stage_only"])["stage"])))
                continue
            if "separate" in h:
                # Hand parity: a STRING separator is carried as a kwarg; a
                # non-string separator atom is dropped entirely.
                if "separator" in h:
                    atom_item, _ = self.atom(h["separator"])
                    if isinstance(atom_item, StringItem):
                        out.append(FuncallRule(name="separate", kwargs={"separator": atom_item.value}))
                        continue
                out.append(FuncallRule(name="separate"))
                continue
            if "case" in h:
                # title_case's kwargs (case_kwargs) are captured by the
                # grammar but ignored by the hand parser — mirrored here.
                out.append(FuncallRule(name=_text(h["case"])))
                continue
            if "compose" in h:
                out.append(FuncallRule(name=_text(h["compose"])))
                continue
            if "funcall_name" in h:
                kwargs: dict[str, str] = {}
                if "funcall_kwargs" in h:
                    # kwarg_list: one captured kwarg collapses to the bare
                    # hash; several arrive as a list of {kwarg: ...} hashes.
                    list_v = _hash(h["funcall_kwargs"])["kwarg"]
                    entries = (
                        [_hash(e)["kwarg"] for e in list_v]
                        if isinstance(list_v, list)
                        else [_hash(list_v)]
                    )
                    for kw in entries:
                        kwargs[_identifier(kw["kwarg_name"])] = self.string(kw["kwarg_value"])
                out.append(FuncallRule(name=_text(h["funcall_name"]), kwargs=kwargs))
                continue
            if "use" in h:
                out.append(self.use_item(_hash(h["use"])))
                continue
            raise ValueError(f"unknown stage item {sorted(h.keys())}")
        return out

    def use_item(self, u: Hash) -> RawUse:
        """A captured use_directive: `use <ident>` / `use <alias>.<ident>`,
        optionally with an override block. Hand parser: `use a.b` names
        the ruleset b, reached through dependency a."""
        name = _identifier(_hash(u["use_alias"]))
        qualified = _identifier(u["qualified_name"]) if "qualified_name" in u else None
        overrides = (
            tuple(self.rule_list(_array(u["use_overrides"])))
            if "use_overrides" in u
            else None
        )
        return RawUse(
            name=qualified if qualified is not None else name,
            dependency_alias=name if qualified is not None else None,
            override=overrides,
        )

    # -- metadata -------------------------------------------------------------------

    def metadata_fields(self, trees: list) -> dict[str, Any]:
        metadata: dict[str, Any] = {}
        for tree in trees:
            h = _hash(tree)
            if "field_name" in h:
                key = _identifier(h["field_name"])
                if "field_value" in h:
                    metadata[key] = self.field_value(h["field_value"], h["field_name"])
                elif "field_block" in h:
                    metadata[key] = self.raw_text(h["field_block"])
                else:
                    metadata[key] = ""
                continue
            if "description" in h:
                metadata["description"] = self.raw_text(h["description"])
                continue
            if "notes" in h:
                # note-list form; an empty block folds to [] — the hand
                # parser's raw-text fallback yields "" (DEVIATION kept).
                notes = [self.string(_hash(n)["note"]) for n in _array(h["notes"])]
                metadata["notes"] = notes if notes else ""
                continue
            if "specification" in h or "provenance" in h:
                # DEVIATION (grammar fidelity): the grammar decodes the
                # comma-separated list; the hand parser only supported a
                # single quoted value (multi-value hit its generic-field
                # scanner error). The corpus is single-valued.
                key = "specification" if "specification" in h else "provenance"
                values = [self.string(_hash(v)[key]) for v in _array(h[key])]
                metadata[key] = values[0] if len(values) == 1 else values
                continue
            if "relations" in h:
                # DEVIATION (grammar fidelity): structured per the grammar;
                # the hand parser rendered the whole block as raw text.
                # The corpus declares no relations blocks (proven by the
                # 434-file parity driver — a raw-vs-structured metadata
                # value would diverge).
                metadata["relations"] = [
                    {
                        "type": _text(_hash(r)["type"]),
                        "system": self.string(_hash(r)["system"]),
                        **({"note": self.string(_hash(r)["note"])} if "note" in _hash(r) else {}),
                    }
                    for r in _array(h["relations"])
                ]
                continue
            if "system_status" in h:
                metadata["system_status"] = _text(h["system_status"])
                continue
            if "code_status" in h:
                metadata["code_status"] = _text(h["code_status"])
                continue
            # String-valued named fields: authority / name / identifying /
            # source_spelling / target_spelling. Dispatched through
            # field_value so a single-quoted value keeps the hand parser's
            # raw-line rendering (see field_value's DEVIATION).
            for key in ("authority", "name", "identifying", "source_spelling", "target_spelling"):
                if key in h:
                    metadata[key] = self.field_value(h[key])
                    break
        return metadata

    def raw_text(self, v: object) -> str:
        """The hand parser's parse_raw_text: a brace-block's raw text with
        `\\{` and `\\}` unescaped, trimmed. An empty block folds to [] (a
        named zero-iteration repetition) and reads as ""."""
        if isinstance(v, Slice):
            content = v.content
        elif isinstance(v, str):
            content = v
        elif isinstance(v, list) and not v:
            return ""
        else:
            raise ValueError(f"unknown raw text {v!r}")
        return content.replace("\\{", "{").replace("\\}", "}").strip()

    def field_value(self, tree: Tree, field_name: Tree | None = None) -> str:
        h = _hash(tree)
        if "raw" in h:
            return _text(h["raw"]).strip()  # type: ignore[arg-type]
        # DEVIATION (hand-parser parity): the hand parser only treated a
        # DOUBLE-quoted value as a quoted string — anything else
        # (single-quoted values, bare words) fell through to its
        # read-to-newline fallback, keeping quotes/spelling verbatim,
        # trimmed. The grammar decodes single-quoted values properly, so
        # dispatch on the SOURCE spelling at the position the hand parser
        # would read from (just past the field name and its inline
        # whitespace): `"` decodes, everything else takes the raw line.
        start = self.value_start(h, field_name)
        if start is not None and self._src[start : start + 1] != '"':
            return self.raw_line_from(start).strip()
        return self.string(tree)

    def value_start(self, h: Hash, field_name: Tree | None) -> int | None:
        """The position the hand parser's value reader starts from: right
        after the field name plus inline whitespace. Anchored on the value
        slice when there is one (the opening quote sits just before it),
        otherwise on the field name."""
        parts = h.get("string")
        if isinstance(parts, list):
            if parts and parts[0] is not None and isinstance(parts[0], dict):
                run = parts[0].get("run")
                if isinstance(run, Slice):
                    return run.offset - 1
            if not parts and field_name is not None:
                identifier = _hash(field_name)["identifier"]
                if isinstance(identifier, Slice):
                    p = identifier.offset + len(identifier.content)
                    while p < len(self._src) and self._src[p] in " \t":
                        p += 1
                    return p
            return None
        if isinstance(parts, Slice):
            return parts.offset - 1
        return None

    def raw_line_from(self, pos: int) -> str:
        """The hand parser's parse_to_newline: from `pos` to the next newline."""
        nl = self._src.find("\n", pos)
        return self._src[pos : nl if nl != -1 else None]

    def test(self, tree: Tree) -> IscTest:
        th = _hash(tree)
        note = self.string(th["note"]) if "note" in th else None
        return IscTest(input=self.string(th["input"]), expected=self.string(th["expected"]), note=note)
