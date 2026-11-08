# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""ISC parser — recursive-descent parser for the `.isc` map DSL.

Port of interscript-ts's `src/isc/parser.ts` (which mirrors the Ruby
Parslet grammar), extended with the ISC-WF-1 workflow constructs:

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
emits `_ir_types` structures directly, so the parse path and the JSON-IR
loader share one runtime representation.

    doc = parse_isc(source, "map.isc")
    doc = parse_isc(source, resolve_dependency=lambda code: other_doc)
    cm = isc_to_compiled_map(doc)   # -> executor.execute_stage(cm, ...)

Parser fidelity notes (mirroring the TypeScript reference):

- Unrecognized tokens in stage/block bodies are silently dropped to end
  of line (Ruby Parslet parity), except the new keywords, which parse.
- `when` joins the keyword table (§2): it is never consumed as a bare
  alias reference in item position.
- `languages` is declared once per map; a second declaration is a parse
  error. `use` may appear in stage bodies, ruleset bodies and inside
  `parallel`/`sequence` blocks; a ruleset whose expansion contains a
  pass block may not itself be used inside a pass block (a nested pass
  has no meaning in the one-simultaneous-pass model).
"""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from ._ir_types import (
    AliasItem,
    AnyCharClassItem,
    AnyItem,
    CaptureGroupItem,
    CaptureRefItem,
    CompiledMap,
    FuncallInline,
    FuncallRule,
    GroupItem,
    ParallelRule,
    RepeatItem,
    RunRule,
    SequentialRule,
    Stage,
    StringItem,
    SubRule,
)
from .errors import IscParseError, MapFormatError

PRIMITIVES = frozenset(
    ["boundary", "line_start", "line_end", "word_boundary", "space", "non_boundary"]
)

FUNCTIONS = frozenset(
    ["upcase", "downcase", "title_case", "reverse", "strip", "swapcase"]
)

CONSTRAINTS = frozenset(["before", "after", "not_before", "not_after"])

# ISC-WF-1 §2: the four new keywords join the keyword table. `use` /
# `override` / `languages` / `ruleset` are handled at their grammar
# positions; `when` can otherwise be reached from item position (right
# after a compact rule's `to`), so it is excluded from alias references.
ITEM_KEYWORDS = frozenset(["when"])

# Words that terminate a comma-less `ident (","? ident)*` list (the
# `languages` declaration and `when` guards). Without this, a one-line
# `languages kur stage main { }` would swallow `stage` as a language.
RESERVED_WORDS = frozenset(
    [
        "metadata", "tests", "aliases", "stage", "dependency", "languages",
        "ruleset", "sub", "use", "run", "parallel", "sequence", "separate",
        "compose", "decompose", "when", "override", "note", "description",
        "notes", "from", "to", "before", "after", "not_before", "not_after",
        "as", "map",
    ]
)

DependencyResolver = Callable[[str], "IscDocument | None"]

# JavaScript \s (the TypeScript parser's whitespace class), kept explicit
# so Python's Unicode \s cannot diverge from the reference.
_WS = frozenset("\t\n\v\f\r \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff")
_WORD = "A-Za-z0-9_"

_RE_WORD = re.compile(f"[{_WORD}]")
_RE_IDENT = re.compile(f"[{_WORD}-]")
_RE_NUMBER = re.compile("[0-9]")


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
# Parser
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
    return _Parser(source, filename, resolve_dependency).parse()


class _Parser:
    def __init__(
        self,
        src: str,
        filename: str | None,
        resolve_dependency: DependencyResolver | None,
    ) -> None:
        self.src = src
        self.pos = 0
        self.filename = filename
        self.resolve_dependency = resolve_dependency
        # Raw (unexpanded) map body, filled by parse().
        self._raw_rulesets: dict[str, list[Any]] = {}
        self._dependencies: list[IscDependency] = []
        self._system_code = ""
        # Memo of fully expanded rulesets (this map only; dependency
        # rulesets arrive already expanded in their own IscDocument).
        self._expanded: dict[str, list[Any]] = {}

    # -- Document ---------------------------------------------------------

    def parse(self) -> IscDocument:
        self.skip_ws()
        self.expect("system")
        self.skip_ws()
        self._system_code = self.parse_quoted_string()
        self.skip_ws()
        self.expect("{")
        body = self.parse_block_items()
        self.skip_ws()
        self.expect("}")
        self.skip_ws()

        metadata: dict[str, Any] = {}
        tests: list[IscTest] = []
        aliases: list[tuple[str, Any]] = []
        raw_stages: list[tuple[str, list[Any]]] = []
        languages: list[str] | None = None

        for item in body:
            tag = item[0]
            if tag == "metadata":
                metadata.update(item[1])
            elif tag == "tests":
                tests = item[1]
            elif tag == "aliases":
                aliases = item[1]
            elif tag == "stage":
                raw_stages.append((item[1], item[2]))
            elif tag == "dependency":
                self._dependencies.append(item[1])
            elif tag == "languages":
                if languages is not None:
                    self.error("languages declared more than once")
                languages = item[1]

        # W1/W2 expansion pass (post-parse: forward references allowed).
        for name in self._raw_rulesets:
            self._expand_ruleset(name)
        stages = [
            IscStage(name=name, items=tuple(self._expand_items(items, (), False)))
            for name, items in raw_stages
        ]

        return IscDocument(
            system_code=self._system_code,
            metadata=metadata,
            tests=tuple(tests),
            aliases=tuple(aliases),
            stages=tuple(stages),
            dependencies=tuple(self._dependencies),
            languages=tuple(languages) if languages is not None else None,
            rulesets={name: tuple(self._expanded[name]) for name in self._raw_rulesets},
        )

    # -- Block items ------------------------------------------------------

    def parse_block_items(self) -> list[Any]:
        items: list[Any] = []
        while True:
            self.skip_ws()
            if self.peek() == "}" or self.pos >= len(self.src):
                break

            keyword = self.peek_word()
            if keyword == "metadata":
                items.append(self.parse_metadata())
            elif keyword == "tests":
                items.append(self.parse_tests())
            elif keyword == "aliases":
                items.append(self.parse_aliases())
            elif keyword == "stage":
                items.append(self.parse_stage())
            elif keyword == "dependency":
                items.append(self.parse_dependency())
            elif keyword == "languages":
                items.append(self.parse_languages())
            elif keyword == "ruleset":
                items.append(self.parse_ruleset())
            else:
                self.error(f"Unexpected keyword: {keyword}")
        return items

    # -- Metadata ---------------------------------------------------------

    def parse_metadata(self) -> Any:
        self.expect("metadata")
        self.skip_ws()
        self.expect("{")
        metadata: dict[str, Any] = {}

        while True:
            self.skip_ws()
            if self.peek() == "}":
                break

            if self.peek_word() == "description":
                self.consume("description")
                self.skip_inline_ws()
                if self.peek() == "{":
                    self.expect("{")
                    metadata["description"] = self.parse_raw_text()
                    self.expect("}")
                elif self.peek() == '"':
                    metadata["description"] = self.parse_quoted_string()
                else:
                    metadata["description"] = self.parse_to_newline().strip()
                continue

            if self.peek_word() == "notes":
                self.consume("notes")
                self.skip_inline_ws()
                if self.peek() == "{":
                    self.expect("{")
                    # Note-list form (`note "..."`) vs raw free text.
                    saved = self.pos
                    self.skip_ws()
                    is_note_list = self.peek_word() == "note"
                    self.pos = saved

                    if is_note_list:
                        notes: list[str] = []
                        while True:
                            self.skip_ws()
                            if self.peek() == "}":
                                break
                            self.expect("note")
                            self.skip_ws()
                            notes.append(self.parse_quoted_string())
                        self.expect("}")
                        metadata["notes"] = notes
                    else:
                        metadata["notes"] = self.parse_raw_text()
                        self.expect("}")
                continue

            key = self.parse_identifier()
            self.skip_inline_ws()
            if self.peek() in ("\n", "}"):
                metadata[key] = ""
                continue
            if self.peek() == "{":
                self.expect("{")
                metadata[key] = self.parse_raw_text()
                self.expect("}")
            elif self.peek() == '"':
                metadata[key] = self.parse_quoted_string()
            else:
                metadata[key] = self.parse_to_newline().strip()
        self.expect("}")
        return ("metadata", metadata)

    # -- Tests ------------------------------------------------------------

    def parse_tests(self) -> Any:
        self.expect("tests")
        self.skip_ws()
        self.expect("{")
        tests: list[IscTest] = []

        while True:
            self.skip_ws()
            if self.peek() == "}":
                break
            if self.peek() == "#":
                self.skip_line()
                continue

            src = self.parse_string_literal()
            self.skip_ws()
            self.expect("->")
            self.skip_ws()
            expected = self.parse_string_literal()
            self.skip_ws()

            if self.peek_word() == "note":
                self.consume("note")
                self.skip_ws()
                tests.append(IscTest(input=src, expected=expected, note=self.parse_string_literal()))
            else:
                tests.append(IscTest(input=src, expected=expected))
        self.expect("}")
        return ("tests", tests)

    # -- Aliases ----------------------------------------------------------

    def parse_aliases(self) -> Any:
        self.expect("aliases")
        self.skip_ws()
        self.expect("{")
        aliases: list[tuple[str, Any]] = []

        while True:
            self.skip_ws()
            if self.peek() == "}":
                break
            if self.peek() == "#":
                self.skip_line()
                continue

            name = self.parse_identifier()
            self.skip_ws()
            self.expect("=")
            self.skip_ws()
            aliases.append((name, self.parse_item(False)))
        self.expect("}")
        return ("aliases", aliases)

    # -- Languages (ISC-WF-1 W3) ------------------------------------------

    def parse_languages(self) -> Any:
        self.expect("languages")
        self.skip_ws()
        names = self.parse_ident_list()
        return ("languages", names)

    def parse_ident_list(self) -> list[str]:
        """`ident (","? ident)*` — the shared list form of `languages` and
        `when`. A comma always continues the list; a comma-less word
        continues it only when it is not a reserved keyword, so a
        one-line declaration cannot swallow the next construct."""
        names = [self.parse_identifier()]
        while True:
            self.skip_inline_ws()
            if self.peek() == ",":
                self.pos += 1
                self.skip_ws()
                names.append(self.parse_identifier())
                continue
            if _RE_IDENT.match(self.peek()) and self.peek_word() not in RESERVED_WORDS:
                names.append(self.parse_identifier())
                continue
            break
        return names

    # -- Stage and ruleset bodies -----------------------------------------

    def parse_stage(self) -> Any:
        self.expect("stage")
        self.skip_ws()
        name = self.parse_identifier()
        self.skip_ws()
        self.expect("{")
        body = self.parse_stage_items()
        self.expect("}")
        return ("stage", name, body)

    def parse_ruleset(self) -> Any:
        """ISC-WF-1 W1: `ruleset <ident> { <stage body items> }`."""
        self.expect("ruleset")
        self.skip_ws()
        name = self.parse_identifier()
        self.skip_ws()
        self.expect("{")
        body = self.parse_stage_items()
        self.expect("}")
        if name in self._raw_rulesets:
            self.error(f"ruleset declared more than once: {name}")
        self._raw_rulesets[name] = body
        return ("ruleset", name)

    def parse_stage_items(self) -> list[Any]:
        """Shared body grammar of `stage` and `ruleset` blocks."""
        body: list[Any] = []
        while True:
            self.skip_ws()
            if self.peek() == "}":
                break
            if self.peek() == "#":
                self.skip_line()
                continue

            keyword = self.peek_word()
            if keyword in ("parallel", "sequence"):
                self.consume(keyword)
                self.skip_ws()
                self.expect("{")
                rules: list[Any] = []
                while True:
                    self.skip_ws()
                    if self.peek() == "}":
                        break
                    if self.peek() == "#":
                        self.skip_line()
                        continue
                    if self.peek_word() == "sub":
                        rules.append(self.parse_rule())
                    elif self.peek_word() == "use":
                        rules.append(self.parse_use())
                    else:
                        # Ruby Parslet silently drops unrecognized tokens
                        # in rule blocks.
                        self.skip_line()
                self.expect("}")
                body.append(ParallelBlock(tuple(rules)) if keyword == "parallel" else SequenceBlock(tuple(rules)))
            elif keyword == "run":
                body.append(self.parse_run())
            elif keyword == "separate":
                self.consume("separate")
                self.skip_ws()
                if self.peek_word() == "separator":
                    self.consume("separator")
                    self.skip_ws()
                    atom = self.parse_item_atom(False)
                    if isinstance(atom, StringItem):
                        body.append(FuncallRule(name="separate", kwargs={"separator": atom.value}))
                    else:
                        body.append(FuncallRule(name="separate"))
                else:
                    body.append(FuncallRule(name="separate"))
            elif keyword in ("compose", "decompose"):
                self.consume(keyword)
                body.append(FuncallRule(name=keyword))
            elif keyword == "rababa":
                self.consume("rababa")
                self.skip_inline_ws()
                kwargs: dict[str, str] = {}
                while self.peek() not in ("}", "", "\n"):
                    arg_name = self.parse_identifier()
                    self.skip_inline_ws()
                    self.expect(":")
                    self.skip_inline_ws()
                    kwargs[arg_name] = self.parse_string_literal()
                    self.skip_inline_ws()
                    if self.peek() == ",":
                        self.pos += 1
                    self.skip_inline_ws()
                body.append(FuncallRule(name="rababa", kwargs=kwargs))
            elif keyword in FUNCTIONS:
                self.consume(keyword)
                body.append(FuncallRule(name=keyword))
            elif keyword == "sub":
                body.append(self.parse_rule())
            elif keyword == "use":
                body.append(self.parse_use())
            else:
                # Ruby Parslet silently drops unrecognized tokens in stage
                # body. Skip to end of line for parity.
                self.skip_line()
        return body

    def parse_run(self) -> RunItem:
        self.consume("run")
        self.skip_ws()
        dep: str | None = None
        if self.peek_word() == "map":
            self.consume("map")
            self.expect(".")
            dep = self.parse_identifier()
            self.expect(".")
            self.expect("stage")
            self.expect(".")
            stage_name = self.parse_identifier()
        elif self.peek_word() == "stage":
            self.consume("stage")
            self.expect(".")
            stage_name = self.parse_identifier()
        else:
            self.error("Expected map. or stage. after run")
        return RunItem(dependency=dep, stage=stage_name)

    # -- Use (ISC-WF-1 W1/W2) ----------------------------------------------

    def parse_use(self) -> RawUse:
        self.expect("use")
        self.skip_ws()
        first = self.parse_identifier()
        dependency_alias: str | None = None
        self.skip_ws()
        if self.peek() == ".":
            self.pos += 1
            self.skip_ws()
            dependency_alias = first
            name = self.parse_identifier()
        else:
            name = first

        override: list[ParsedRule] | None = None
        self.skip_ws()
        if self.peek_word() == "override":
            self.consume("override")
            self.skip_ws()
            self.expect("{")
            override = []
            while True:
                self.skip_ws()
                if self.peek() == "}":
                    break
                if self.peek() == "#":
                    self.skip_line()
                    continue
                if self.peek_word() == "sub":
                    override.append(self.parse_rule())
                else:
                    self.skip_line()
            self.expect("}")
        return RawUse(
            name=name,
            dependency_alias=dependency_alias,
            override=tuple(override) if override is not None else None,
        )

    # -- Rules --------------------------------------------------------------

    def parse_rule(self) -> ParsedRule:
        self.expect("sub")
        self.skip_ws()
        from_source: str | None = None
        when: tuple[str, ...] | None = None

        # Block form: sub { from ... to ... }
        if self.peek() == "{":
            self.expect("{")
            from_: Any = StringItem(value="")
            to: Any = StringItem(value="")
            constraints: list[tuple[str, Any]] = []

            while True:
                self.skip_ws()
                if self.peek() == "}":
                    break

                word = self.peek_word()
                if word == "from":
                    self.consume("from")
                    self.skip_ws()
                    from_ = self.parse_item(False)
                elif word == "to":
                    self.consume("to")
                    self.skip_ws()
                    to = self.parse_item(True)
                elif word in CONSTRAINTS:
                    self.consume(word)
                    self.skip_ws()
                    constraints.append((word, self.parse_item(False)))
                else:
                    self.error(f"Unexpected keyword in sub block: {word}")
            self.expect("}")
            self.skip_ws()
            if self.peek_word() == "when":
                self.consume("when")
                self.skip_ws()
                when = tuple(self.parse_ident_list())
            return ParsedRule(
                rule=_make_sub_rule(from_, to, constraints, when),
                from_source=None,
            )

        # Compact form: sub <from> <to> <constraints> [when ...]
        start = self.pos
        from_ = self.parse_item_atom(False)
        from_source = self.src[start : self.pos].strip()
        self.skip_ws()
        to = self.parse_item_atom(True)
        constraints: list[tuple[str, Any]] = []

        while True:
            self.skip_ws()
            word = self.peek_word()
            if word not in CONSTRAINTS:
                break
            self.consume(word)
            self.skip_ws()
            constraints.append((word, self.parse_item_atom(False)))

        self.skip_ws()
        if self.peek_word() == "when":
            self.consume("when")
            self.skip_ws()
            when = tuple(self.parse_ident_list())

        return ParsedRule(
            rule=_make_sub_rule(from_, to, constraints, when),
            from_source=from_source,
        )

    # -- Items ---------------------------------------------------------------

    def parse_item(self, to_position: bool) -> Any:
        first, first_kind = self.parse_item_atom_raw()
        parts = [first]
        kinds = [first_kind]

        while True:
            self.skip_inline_ws()
            if self.peek() == "+":
                self.pos += 1
                self.skip_inline_ws()
                atom, kind = self.parse_item_atom_raw()
                parts.append(atom)
                kinds.append(kind)
            elif self._is_item_atom_start() and not self._is_keyword():
                atom, kind = self.parse_item_atom_raw()
                parts.append(atom)
                kinds.append(kind)
            else:
                break

        if len(parts) == 1:
            return _function_to_inline(parts[0], kinds[0]) if to_position else parts[0]
        return GroupItem(items=tuple(parts))

    def parse_item_atom(self, to_position: bool) -> Any:
        atom, kind = self.parse_item_atom_raw()
        return _function_to_inline(atom, kind) if to_position else atom

    def parse_item_atom_raw(self) -> tuple[Any, str]:
        """One item atom -> (IR item, parse kind). Function atoms keep
        their kind so the `to` position can lower them to FuncallInline
        (mirrors converter.ts); elsewhere they fall back to alias lookup
        so a clear error surfaces at runtime."""
        c = self.peek()

        if c in ('"', "'"):
            return StringItem(value=self.parse_string_literal()), "string"

        word = self.peek_word()
        if not word:
            self.error("Expected item atom")

        if word in ITEM_KEYWORDS:
            self.error(f"Unexpected keyword in item position: {word}")

        if word == "none":
            self.consume("none")
            # converter.ts lowers `none` to the empty string.
            return StringItem(value=""), "string"
        if word == "any_character":
            self.consume("any_character")
            return AliasItem(name="any_character"), "function"

        if word == "any":
            self.consume("any")
            self.expect("(")
            self.skip_ws()
            inner = self.peek()
            # any("...".."...") or any('...'..'...') — range from strings
            if inner in ('"', "'"):
                lo = self.parse_string_literal()
                self.skip_ws()
                if self.src.startswith("..", self.pos):
                    self.pos += 2
                    self.skip_ws()
                    hi = self.parse_string_literal()
                    self.skip_ws()
                    self.expect(")")
                    return AnyCharClassItem(range=(lo, hi)), "item"
                self.expect(")")
                # any("abc") — split into per-char string items
                return (
                    AnyItem(of=tuple(StringItem(value=ch) for ch in lo)),
                    "item",
                )
            if inner == "[":
                self.expect("[")
                items: list[Any] = []
                while True:
                    self.skip_ws()
                    if self.peek() == "]":
                        break
                    items.append(self.parse_item(False))
                    self.skip_ws()
                    if self.peek() == ",":
                        self.pos += 1
                self.expect("]")
                self.skip_ws()
                self.expect(")")
                return AnyItem(of=tuple(items)), "item"
            # any(item), any(item + item), any(alias_name), any(range..)
            item = self.parse_item(False)
            self.skip_ws()
            self.expect(")")
            return AnyItem(of=(item,)), "item"

        if word == "capture":
            self.consume("capture")
            self.expect("(")
            self.skip_ws()
            inner = self.parse_item(False)
            self.skip_ws()
            self.expect(")")
            return CaptureGroupItem(data=inner), "item"

        if word == "maybe":
            self.consume("maybe")
            self.expect("(")
            self.skip_ws()
            inner = self.parse_item(False)
            self.skip_ws()
            self.expect(")")
            return RepeatItem(item=inner, min=0, max=1), "item"

        if word == "some":
            self.consume("some")
            self.expect("(")
            self.skip_ws()
            inner = self.parse_item(False)
            self.skip_ws()
            self.expect(")")
            return RepeatItem(item=inner, min=1, max=None), "item"

        if word == "ref":
            self.consume("ref")
            self.expect("(")
            self.skip_ws()
            num = self.parse_number()
            self.skip_ws()
            self.expect(")")
            return CaptureRefItem(id=num), "item"

        if word in PRIMITIVES:
            self.consume(word)
            return AliasItem(name=word), "item"

        if word in FUNCTIONS:
            self.consume(word)
            return AliasItem(name=word), "function"

        # Alias reference
        self.consume(word)
        return AliasItem(name=word), "item"

    # -- Dependency --------------------------------------------------------

    def parse_dependency(self) -> Any:
        self.expect("dependency")
        self.skip_ws()
        target = self.parse_quoted_string()
        self.skip_inline_ws()
        alias_name: str | None = None
        if self.peek_word() == "as":
            self.consume("as")
            self.skip_ws()
            alias_name = self.parse_identifier()
        return ("dependency", IscDependency(target=target, alias_name=alias_name))

    # -- String primitives ---------------------------------------------------

    def parse_string_literal(self) -> str:
        c = self.peek()
        if c == '"':
            return self.parse_quoted_string()
        if c == "'":
            return self.parse_single_quoted_string()
        self.error(f'Expected string but got "{self.src[self.pos : self.pos + 20]}"')

    def parse_quoted_string(self) -> str:
        self.expect('"')
        result: list[str] = []
        while self.pos < len(self.src):
            c = self.src[self.pos]
            self.pos += 1
            if c == '"':
                return "".join(result)
            if c == "\\":
                if self.pos >= len(self.src):
                    break
                nxt = self.src[self.pos]
                self.pos += 1
                if nxt == "n":
                    result.append("\n")
                elif nxt == "t":
                    result.append("\t")
                elif nxt == "r":
                    result.append("\r")
                elif nxt == '"':
                    result.append('"')
                elif nxt == "\\":
                    result.append("\\")
                elif nxt == "u":
                    hex_ = self.src[self.pos : self.pos + 4]
                    self.pos += 4
                    try:
                        result.append(chr(int(hex_, 16)))
                    except ValueError:
                        result.append("\0")
                elif nxt == "{":
                    result.append("{")
                elif nxt == "}":
                    result.append("}")
                else:
                    result.append(nxt)
            else:
                result.append(c)
        self.error("Unterminated string")

    def parse_single_quoted_string(self) -> str:
        self.expect("'")
        start = self.pos
        while self.pos < len(self.src) and self.src[self.pos] != "'":
            self.pos += 1
        result = self.src[start : self.pos]
        self.expect("'")
        return result

    def parse_raw_text(self) -> str:
        result: list[str] = []
        depth = 0
        while self.pos < len(self.src):
            c = self.src[self.pos]
            if c == "\\" and self.pos + 1 < len(self.src):
                nxt = self.src[self.pos + 1]
                if nxt in "{}":
                    result.append(nxt)
                    self.pos += 2
                    continue
            if c == "}" and depth == 0:
                break
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            result.append(c)
            self.pos += 1
        return "".join(result).strip()

    def parse_identifier(self) -> str:
        self.skip_ws()
        start = self.pos
        while self.pos < len(self.src) and _RE_IDENT.match(self.src[self.pos]):
            self.pos += 1
        if self.pos == start:
            self.error("Expected identifier")
        return self.src[start : self.pos]

    def parse_number(self) -> int:
        start = self.pos
        while self.pos < len(self.src) and _RE_NUMBER.match(self.src[self.pos]):
            self.pos += 1
        return int(self.src[start : self.pos] or "0", 10)

    def parse_to_newline(self) -> str:
        start = self.pos
        while self.pos < len(self.src) and self.src[self.pos] != "\n":
            self.pos += 1
        return self.src[start : self.pos]

    # -- W1/W2 expansion -----------------------------------------------------

    def _expand_ruleset(self, name: str, chain: tuple[tuple[str, str], ...] = ()) -> list[Any]:
        entry = (self._system_code, name)
        if entry in chain:
            self.error(f"use cycle: {' -> '.join(f'{m}/{r}' for m, r in (*chain, entry))}")
        cached = self._expanded.get(name)
        if cached is not None:
            return cached
        raw = self._raw_rulesets.get(name)
        if raw is None:
            self.error(f"unknown ruleset: {name}")
        expanded = self._expand_items(raw, chain + (entry,), False)
        self._expanded[name] = expanded
        return expanded

    def _expand_items(
        self, items: list[Any], chain: tuple[tuple[str, str], ...], in_block: bool
    ) -> list[Any]:
        out: list[Any] = []
        for it in items:
            if isinstance(it, RawUse):
                out.extend(self._expand_use(it, chain, in_block))
                continue
            if in_block and isinstance(it, (ParallelBlock, SequenceBlock)):
                self.error(
                    "a ruleset containing a parallel/sequence block cannot be "
                    "used inside a parallel/sequence block"
                )
            if isinstance(it, (ParallelBlock, SequenceBlock)):
                it = type(it)(rules=tuple(self._expand_items(list(it.rules), chain, True)))
            out.append(it)
        return out

    def _expand_use(
        self, use: RawUse, chain: tuple[tuple[str, str], ...], in_block: bool
    ) -> list[Any]:
        if use.dependency_alias is not None:
            expanded = self._expand_via_dependency(use, chain)
        else:
            expanded = self._expand_ruleset(use.name, chain)

        if in_block and any(isinstance(x, (ParallelBlock, SequenceBlock)) for x in expanded):
            self.error(
                "a ruleset containing a parallel/sequence block cannot be used "
                "inside a parallel/sequence block"
            )

        if use.override is not None:
            expanded = self._apply_override(expanded, list(use.override))
        return list(expanded)

    def _expand_via_dependency(
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
        """ISC-WF-1 §4.2 merge: R_kept (in R's order) followed by O (in
        O's order); ALL rules sharing an override's from-string are
        replaced. For rows inside a parallel/sequence block the matched
        overrides are appended at that block's end so they stay in the
        pass where the replaced row lived (§4.3); overrides matching
        nothing are simply added at the end (§4.2 rule 4)."""
        okeys = [self._from_key(o) for o in overrides]
        placed: set[int] = set()
        out: list[Any] = []
        for it in items:
            if isinstance(it, ParsedRule):
                if self._from_key(it) in okeys:
                    continue
                out.append(it)
            elif isinstance(it, (ParallelBlock, SequenceBlock)):
                kept: list[Any] = []
                dropped_keys: set[Any] = set()
                for r in it.rules:
                    if isinstance(r, ParsedRule) and self._from_key(r) in okeys:
                        dropped_keys.add(self._from_key(r))
                    else:
                        kept.append(r)
                block_overrides: list[ParsedRule] = []
                for i, o in enumerate(overrides):
                    if i not in placed and self._from_key(o) in dropped_keys:
                        block_overrides.append(o)
                        placed.add(i)
                out.append(type(it)(rules=tuple(kept + block_overrides)))
            else:
                out.append(it)
        for i, o in enumerate(overrides):
            if i not in placed:
                out.append(o)
        return out

    # -- Scanner helpers (mirror the TypeScript parser) ----------------------

    def char_at(self, i: int) -> str:
        return self.src[i] if i < len(self.src) else ""

    def peek(self) -> str:
        return self.char_at(self.pos)

    def peek_word(self) -> str:
        start = self.pos
        while self.pos < len(self.src) and _RE_WORD.match(self.src[self.pos]):
            self.pos += 1
        word = self.src[start : self.pos]
        self.pos = start
        return word

    def expect(self, s: str) -> None:
        self.skip_ws()
        if not self.src.startswith(s, self.pos):
            self.error(f'Expected "{s}" but got "{self.src[self.pos : self.pos + 20]}"')
        self.pos += len(s)

    def consume(self, word: str) -> None:
        if not self.src.startswith(word, self.pos):
            self.error(f'Expected "{word}"')
        self.pos += len(word)

    def skip_ws(self) -> None:
        while self.pos < len(self.src):
            c = self.src[self.pos]
            if c in _WS:
                self.pos += 1
                continue
            if c == "#":
                self.skip_line()
                continue
            break

    def skip_inline_ws(self) -> None:
        while self.pos < len(self.src) and self.src[self.pos] in " \t":
            self.pos += 1

    def skip_line(self) -> None:
        while self.pos < len(self.src) and self.src[self.pos] != "\n":
            self.pos += 1
        if self.pos < len(self.src):
            self.pos += 1

    def _is_item_atom_start(self) -> bool:
        c = self.peek()
        if not c:
            return False
        return c in ('"', "'") or bool(_RE_WORD.match(c))

    def _is_keyword(self) -> bool:
        word = self.peek_word()
        return word in ("to", "from", "before", "after", "not_before", "not_after", "note")

    def error(self, msg: str) -> None:
        line = self.src[: self.pos].count("\n") + 1
        col = self.pos - self.src.rfind("\n", 0, self.pos)
        full_msg = f"{self.filename}: {msg}" if self.filename else msg
        raise IscParseError(full_msg, self.pos, line, col)


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
