# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Reader for the parsanol grammar language (PARG) — the text format the
canonical ISC grammar (isc.parg) is written in.

This is a Python port of the relevant subset of Parsanol::PARG
(lexer.rb + parser.rb + compiler.rb's parse_hex), mirrored from
interscript-ts's src/isc/grammar/parg-reader.ts and pinned to the
constructs the ISC grammar uses:

    - the `grammar <name> version "..." { ... }` envelope
    - `entry <name>: <rule>` declarations
    - rules: `name = expression`, terminated by newline (ABNF/PEG mix:
      ordered choice `/`, sequences, `[x]` optional, `n*m` repetition,
      `!x`/`&x` lookaheads, `expr as name` captures, string literals,
      `%xNN-NN` character ranges, rule references)

Anything outside that subset (states, tables, preprocess, render,
derive, brace rule bodies, `%i`/`%s` literals, categories) raises a
PargParseError naming the construct — the reader fails loudly instead
of silently misparsing a grammar it does not understand.

The AST node kinds mirror the compiled atom graph (see peg.py for the
interpreter and the flattening semantics it reproduces):

    Lit(s)                 literal string
    CharClass(ranges)      single character class
    Seq(parts)             ordered sequence
    Alt(branches)          ordered choice (PEG)
    Rep(body, min, max)    repetition (max None = open)
    Pred(positive, body)   lookahead, zero-width
    Cap(name, body)        named capture
    Ref(name)              rule reference
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


class PargParseError(ValueError):
    """The PARG text itself is malformed (or uses an unsupported construct)."""


# ---------------------------------------------------------------------------
# AST
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Lit:
    s: str


@dataclass(frozen=True, slots=True)
class CharClass:
    ranges: tuple[tuple[int, int], ...]


@dataclass(frozen=True, slots=True)
class Seq:
    a: tuple


@dataclass(frozen=True, slots=True)
class Alt:
    a: tuple


@dataclass(frozen=True, slots=True)
class Rep:
    a: object
    min: int
    max: int | None
    maybe: bool = False


@dataclass(frozen=True, slots=True)
class Pred:
    positive: bool
    a: object


@dataclass(frozen=True, slots=True)
class Cap:
    name: str
    a: object


@dataclass(frozen=True, slots=True)
class Ref:
    name: str


@dataclass
class PargGrammar:
    name: str = ""
    version: str = ""
    # entry name -> root rule name (the ISC grammar declares `entry isc: isc_source`)
    entries: dict[str, str] = field(default_factory=dict)
    # rule name -> AST
    rules: dict[str, object] = field(default_factory=dict)
    # declaration order, for diagnostics
    order: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Lexer — token classes mirror Parsanol::PARG::Lexer (comments and
# whitespace dropped, newlines kept as separators).
# ---------------------------------------------------------------------------

_HEX_RE = re.compile(r"%x[0-9A-Fa-f]{2,6}(?:-[0-9A-Fa-f]{2,6}|(?:\.[0-9A-Fa-f]{2,6})+)?")
_STR_RE = re.compile(r'"(?:[^"\\]|\\.)*"')
_SSTR_RE = re.compile(r'%s"(?:[^"\\]|\\.)*"')
_NUM_RE = re.compile(r"\d+")
_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_PUNCT_RE = re.compile(r"[=/()\[\]{}*!&:,.<-]")

# (type, value, offset) — offset into the source text, for diagnostics


def _lex(text: str) -> list[tuple[str, str, int]]:
    tokens: list[tuple[str, str, int]] = []
    pos = 0
    n = len(text)
    while pos < n:
        c = text[pos]
        if c == "\n" or (c == "\r" and text[pos + 1 : pos + 2] == "\n"):
            tokens.append(("newline", "\n", pos))
            pos += 2 if c == "\r" else 1
            continue
        if c in " \t":
            pos += 1
            continue
        if c == "#":
            while pos < n and text[pos] != "\n":
                pos += 1
            continue
        if c == "%":
            if text.startswith('%s"', pos):
                m = _SSTR_RE.match(text, pos)
                if m is None:
                    raise PargParseError(f'unterminated %s"..." literal at offset {pos}')
                tokens.append(("sstr", m.group(0)[3:-1], pos))
                pos = m.end()
                continue
            if text.startswith('%i"', pos):
                raise PargParseError(
                    f'%i"..." case-insensitive literals are not supported by this reader (offset {pos})'
                )
            if text.startswith("%p{", pos):
                raise PargParseError(
                    f"%p{{...}} category classes are not supported by this reader (offset {pos})"
                )
            m = _HEX_RE.match(text, pos)
            if m is not None:
                tokens.append(("hex", m.group(0)[2:], pos))
                pos = m.end()
                continue
            raise PargParseError(f"unexpected %-construct at offset {pos}")
        if c == '"':
            m = _STR_RE.match(text, pos)
            if m is None:
                raise PargParseError(f"unterminated string literal at offset {pos}")
            tokens.append(("str", m.group(0)[1:-1], pos))
            pos = m.end()
            continue
        if c in "0123456789":
            # ASCII digits only (Python's str.isdigit is Unicode-aware; the
            # PARG number token is %x30-39, mirroring the ts lexer's \d).
            m = _NUM_RE.match(text, pos)
            tokens.append(("num", m.group(0), pos))
            pos = m.end()
            continue
        if ("a" <= c <= "z") or ("A" <= c <= "Z") or c == "_":
            m = _IDENT_RE.match(text, pos)
            tokens.append(("ident", m.group(0), pos))
            pos = m.end()
            continue
        m = _PUNCT_RE.match(text, pos)
        if m is not None:
            tokens.append(("punct", m.group(0), pos))
            pos += 1
            continue
        raise PargParseError(f"unexpected character {c!r} at offset {pos}")
    return tokens


def _unquote(raw: str) -> str:
    """Unquote a literal body: \\n \\t \\r are escapes, anything else is itself."""
    out: list[str] = []
    i = 0
    n = len(raw)
    while i < n:
        c = raw[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        i += 1
        nxt = raw[i] if i < n else ""
        i += 1
        if nxt == "n":
            out.append("\n")
        elif nxt == "t":
            out.append("\t")
        elif nxt == "r":
            out.append("\r")
        else:
            out.append(nxt)
    return "".join(out)


# ---------------------------------------------------------------------------
# Parser — mirrors Parsanol::PARG::Parser productions for the supported
# subset. Sequences end at a newline (outside `(...)` grouping, which the
# ISC grammar never spans), `/`, `)`, `]` or `}`.
# ---------------------------------------------------------------------------


class _PargParser:
    def __init__(self, text: str) -> None:
        self._tokens = _lex(text)
        self._pos = 0
        self.grammar = PargGrammar()

    def _peek(self) -> tuple[str, str, int] | None:
        return self._tokens[self._pos] if self._pos < len(self._tokens) else None

    def _advance(self) -> tuple[str, str, int]:
        if self._pos >= len(self._tokens):
            raise PargParseError("unexpected end of grammar")
        tok = self._tokens[self._pos]
        self._pos += 1
        return tok

    def _expect(self, type_: str, value: str | None = None) -> tuple[str, str, int]:
        tok = self._advance()
        if tok[0] != type_ or (value is not None and tok[1] != value):
            found = f"{tok[0]}:{tok[1]!r}"
            expected = repr(value) if value is not None else type_
            raise PargParseError(f"expected {expected}, got {found} at offset {tok[2]}")
        return tok

    def _skip_newlines(self) -> None:
        while (tok := self._peek()) is not None and tok[0] == "newline":
            self._pos += 1

    def parse(self) -> PargGrammar:
        self._skip_newlines()
        while self._pos < len(self._tokens):
            section = self._advance()
            if section[0] != "ident":
                raise PargParseError(
                    f"expected a section (grammar/entry), got {section[0]} at offset {section[2]}"
                )
            if section[1] == "grammar":
                self._parse_grammar()
            elif section[1] == "entry":
                self._parse_entry()
            else:
                raise PargParseError(
                    f'unsupported PARG section "{section[1]}" at offset {section[2]} '
                    f"(this reader implements grammar/entry only)"
                )
            self._skip_newlines()
        return self.grammar

    def _parse_grammar(self) -> None:
        self.grammar.name = self._expect("ident")[1]
        self._expect("ident", "version")
        self.grammar.version = _unquote(self._expect("str")[1])
        # `edition` is accepted and ignored when present (RS vendored copy
        # carries `edition "v1"`; the canonical ISC grammar omits it).
        tok = self._peek()
        if tok is not None and tok[0] == "ident" and tok[1] == "edition":
            self._advance()
            tok = self._advance()
            if tok[0] not in ("str", "num"):
                raise PargParseError(f'expected edition value after "edition" at offset {tok[2]}')
        self._expect("punct", "{")
        self._skip_newlines()
        while not ((tok := self._peek()) is not None and tok[0] == "punct" and tok[1] == "}"):
            if self._peek() is None:
                raise PargParseError("unterminated grammar block")
            if (tok := self._peek())[0] == "ident" and tok[1] == "entry":
                self._advance()
                self._parse_entry()
                self._skip_newlines()
                continue
            self._parse_rule()
            self._skip_newlines()
        self._expect("punct", "}")

    def _parse_entry(self) -> None:
        name = self._expect("ident")[1]
        self._expect("punct", ":")
        tok = self._expect("ident")
        self.grammar.entries[name] = tok[1]

    def _parse_rule(self) -> None:
        name = self._expect("ident")[1]
        self._expect("punct", "=")
        if name in self.grammar.rules:
            raise PargParseError(f"duplicate rule {name!r}")
        self.grammar.rules[name] = self._parse_choice()
        self.grammar.order.append(name)

    def _stop_element(self) -> bool:
        tok = self._peek()
        if tok is None:
            return True
        if tok[0] == "newline":
            return True
        return tok[0] == "punct" and tok[1] in ("/", ")", "]", "}")

    def _parse_choice(self) -> object:
        branches = [self._parse_seq()]
        while (tok := self._peek()) is not None and tok[0] == "punct" and tok[1] == "/":
            self._advance()
            branches.append(self._parse_seq())
        return branches[0] if len(branches) == 1 else Alt(tuple(branches))

    def _parse_seq(self) -> object:
        if self._stop_element():
            tok = self._peek()
            raise PargParseError(f"empty sequence at offset {tok[2] if tok else -1}")
        items = [self._parse_element()]
        while not self._stop_element():
            items.append(self._parse_element())
        return items[0] if len(items) == 1 else Seq(tuple(items))

    def _parse_element(self) -> object:
        tok = self._peek()
        if tok is None:
            raise PargParseError("unexpected end of input inside sequence")
        if tok[0] == "num":
            self._advance()
            mn = int(tok[1])
            nxt = self._peek()
            if nxt is not None and nxt[0] == "punct" and nxt[1] == "*":
                self._advance()
                nxt = self._peek()
                mx = int(self._advance()[1]) if nxt is not None and nxt[0] == "num" else None
                return self._capture_postfix(Rep(self._parse_rep_body(), mn, mx))
            return self._capture_postfix(Rep(self._parse_rep_body(), mn, mn))
        if tok[0] == "punct" and tok[1] == "*":
            self._advance()
            nxt = self._peek()
            mx = int(self._advance()[1]) if nxt is not None and nxt[0] == "num" else None
            return self._capture_postfix(Rep(self._parse_rep_body(), 0, mx))
        return self._parse_postfixed()

    def _parse_rep_body(self) -> object:
        """A repetition's body is a guarded primary; it takes no `as` postfix."""
        sign, node = self._parse_guard_sign()
        if sign is None:
            return node
        return Pred(sign, node)

    def _parse_guard_sign(self) -> tuple[bool | None, object]:
        tok = self._peek()
        if tok is not None and tok[0] == "punct" and tok[1] in ("!", "&"):
            self._advance()
            return (tok[1] == "&", self._parse_primary())
        return (None, self._parse_primary())

    def _capture_postfix(self, node: object) -> object:
        tok = self._peek()
        if tok is not None and tok[0] == "ident" and tok[1] == "as":
            self._advance()
            name = self._expect("ident")[1]
            return Cap(name, node)
        return node

    def _parse_postfixed(self) -> object:
        sign, node = self._parse_guard_sign()
        if sign is None:
            return self._capture_postfix(node)
        # The capture binds the guard, not the guarded primary (parsanol-ruby#380).
        return self._capture_postfix(Pred(sign, node))

    def _parse_primary(self) -> object:
        tok = self._advance()
        kind, value, offset = tok
        if kind == "str":
            return Lit(_unquote(value))
        if kind == "sstr":
            return Lit(value)
        if kind == "hex":
            return self._parse_hex(value)
        if kind == "punct":
            if value == "(":
                node = self._parse_choice()
                self._expect("punct", ")")
                return node
            if value == "[":
                node = self._parse_choice()
                self._expect("punct", "]")
                return Rep(node, 0, 1, maybe=True)
            raise PargParseError(f"unexpected {value!r} in expression at offset {offset}")
        if kind == "ident":
            if value == "until":
                raise PargParseError(f'"until" is not supported by this reader (offset {offset})')
            if value in ("alt", "state", "set", "switch"):
                raise PargParseError(f'"{value}" is not supported by this reader (offset {offset})')
            return Ref(value)
        raise PargParseError(f"unexpected token {kind}:{value!r} at offset {offset}")

    def _parse_hex(self, spec: str) -> object:
        """`%xNN-NN` range, `%xNN.NN` sequence of single-char classes, `%xNN` single."""
        if "-" in spec:
            lo, hi = spec.split("-", 1)
            if not lo or not hi:
                raise PargParseError(f"malformed hex range %x{spec}")
            return CharClass(((int(lo, 16), int(hi, 16)),))
        if "." in spec:
            parts = tuple(CharClass(((int(h, 16), int(h, 16)),)) for h in spec.split("."))
            return parts[0] if len(parts) == 1 else Seq(parts)
        code = int(spec, 16)
        return CharClass(((code, code),))


def parse_parg(text: str) -> PargGrammar:
    """Read a PARG text into a grammar table."""
    return _PargParser(text).parse()
