# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Standard library — port of interscript-ts's `src/stdlib.ts`, which is
itself a port of `interscript-ruby/lib/interscript/stdlib.rb`.

Pure functions: no global state, no side effects. Regexes are compiled
with the third-party `regex` module because the corpus relies on
Unicode categories (`\\p{L}`) and variable-width lookbehind, neither of
which stdlib `re` supports.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Protocol

import regex

# Flags mirror the TS runtime's "gmu": global (Python replace is global
# by default), multiline, unicode (Python 3 str patterns are Unicode).
REGEX_FLAGS = regex.MULTILINE | regex.VERSION0 | regex.UNICODE

_ESCAPE_RE = regex.compile(r"[.*+?^${}()|\[\]\\]")


def regexp_escape(text: str) -> str:
    """Escape a string so it matches literally inside a regex.

    Mirrors TS `regexpEscape` (the same minimal char set, NOT Python's
    `re.escape`, which over-escapes and would change nothing semantically
    but keep the two engines' pattern strings comparable).
    """
    return _ESCAPE_RE.sub(lambda m: "\\" + m.group(0), text)


# ---------------------------------------------------------------------------
# Parallel replace — trie (single pass, longest match wins)
# ---------------------------------------------------------------------------


@dataclass
class _TrieNode:
    children: dict[int, _TrieNode]
    match: str | None = None


def compile_parallel_tree(pairs: list[tuple[str, str]]) -> _TrieNode:
    """Build a trie from (from, to) pairs. Port of
    `Interscript::Stdlib.parallel_replace_compile_tree`."""
    root = _TrieNode(children={})
    for src, dst in pairs:
        if not src:
            continue
        branch = root
        for ch in src[:-1]:
            node = branch.children.get(ord(ch))
            if node is None:
                node = _TrieNode(children={})
                branch.children[ord(ch)] = node
            branch = node
        leaf = branch.children.get(ord(src[-1]))
        if leaf is None:
            leaf = _TrieNode(children={})
            branch.children[ord(src[-1])] = leaf
        leaf.match = dst
    return root


def parallel_replace_tree(text: str, tree: _TrieNode) -> str:
    """Walk `text` against the trie, emitting the longest match at each
    position. Port of `Interscript::Stdlib.parallel_replace_tree`."""
    out: list[str] = []
    length = len(text)
    i = 0
    while i < length:
        branch = tree
        match_len = 0
        match_repl: str | None = None
        j = 0
        while i + j < length:
            nxt = branch.children.get(ord(text[i + j]))
            if nxt is None:
                break
            branch = nxt
            if branch.match is not None:
                match_len = j + 1
                match_repl = branch.match
            j += 1
        if match_repl is not None and match_len > 0:
            out.append(match_repl)
            i += match_len
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def parallel_replace(text: str, pairs: list[tuple[str, str]]) -> str:
    if not pairs:
        return text
    return parallel_replace_tree(text, compile_parallel_tree(pairs))


# ---------------------------------------------------------------------------
# Megaregexp parallel replace (constrained parallel blocks)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MegaregexpRule:
    pattern: str
    replace: Callable[[str, list[str | None]], str]


def parallel_megaregexp(text: str, rules: list[MegaregexpRule]) -> str:
    """One alternation of every rule's pattern; at each position the
    first (declaration-order) alternative that matches wins. Mirrors
    Ruby's `parallel_regexp_compile` + `parallel_regexp_gsub` and the TS
    `parallelMegaregexp`.

    Each alternative is wrapped in a uniquely-named group so the
    callback can tell which rule matched. The wrappers occupy the
    leading slots of the global numbered-group list, so the replacement
    receives only the SLICE of groups belonging to the matched rule's
    own pattern (rs semantics, WO18 G1): `$1` templates resolve against
    the rule's first capture, never the wrapper's whole match.
    """
    if not rules:
        return text
    parts = [f"(?P<__r{i}>{r.pattern})" for i, r in enumerate(rules)]
    mega = regex.compile("|".join(parts), REGEX_FLAGS)
    n_groups = mega.groups

    # Numbered groups BEFORE each rule's wrapper: one wrapper per
    # earlier rule plus each earlier rule's inner captures. The wrapper
    # itself is global group (base + 1) — list index base — so the
    # rule's own captures occupy list slice [base + 1, base + 1 + n).
    # Compiling each pattern on its own yields its exact group count —
    # the same grammar the alternation embeds.
    offsets: list[tuple[int, int]] = []
    base = 0
    for r in rules:
        n = regex.compile(r.pattern, REGEX_FLAGS).groups
        offsets.append((base + 1, n))
        base += 1 + n

    def _sub(m: regex.Match) -> str:
        for i, rule in enumerate(rules):
            if m.group(f"__r{i}") is not None:
                start, n = offsets[i]
                captures = [m.group(k) for k in range(1, n_groups + 1)]
                return rule.replace(m.group(0), captures[start : start + n])
        return m.group(0)

    return mega.sub(_sub, text)


# ---------------------------------------------------------------------------
# Builtin functions (Interscript.functions.*)
# ---------------------------------------------------------------------------


def downcase(text: str, opts: dict | None = None) -> str:
    return text.lower()


def upcase(text: str, opts: dict | None = None) -> str:
    return text.upper()


def title_case(text: str, opts: dict | None = None) -> str:
    """`Interscript::Stdlib::Functions.title_case` / rs `title_case`
    parity: upcase the FIRST character of the string, then the
    character following each word separator. Other characters are
    untouched (ruby `gsub(/^(.)/)` + `gsub(/#{sep}(.)/)` — notably NOT
    full per-word title-casing)."""
    sep = (opts or {}).get("wordSeparator", " ")
    chars = list(text)
    if chars:
        chars[0] = chars[0].upper()
    if sep == "":
        return "".join(chars)
    sep_chars = list(sep)
    out: list[str] = []
    i = 0
    while i < len(chars):
        if i + len(sep_chars) < len(chars) and chars[i : i + len(sep_chars)] == sep_chars:
            out.append(sep)
            out.append(chars[i + len(sep_chars)].upper())
            i += len(sep_chars) + 1
        else:
            out.append(chars[i])
            i += 1
    return "".join(out)


def separate(text: str, opts: dict | None = None) -> str:
    sep = (opts or {}).get("separator", " ")
    return sep.join(text)


def unseparate(text: str, opts: dict | None = None) -> str:
    """Remove every separator (the inverse of `separate`).
    `Interscript.functions.unseparate` — used by reverse mode
    (`Stdlib.reverse_function` maps separate <-> unseparate). Split
    semantics mirror rs/ruby: trailing empty segments survive the split
    and rejoin (no trimming)."""
    sep = (opts or {}).get("separator", " ")
    return "".join(text.split(sep))


def compose(text: str, opts: dict | None = None) -> str:
    import unicodedata

    return unicodedata.normalize("NFC", text)


def decompose(text: str, opts: dict | None = None) -> str:
    import unicodedata

    return unicodedata.normalize("NFD", text)


# Ruby String#strip's character set: null, horizontal tab, line feed,
# vertical tab, form feed, carriage return, space (ASCII set only —
# deliberately NOT python's default Unicode-whitespace strip).
_RUBY_STRIP_SET = "\0\t\n\v\f\r "


def reverse(text: str, opts: dict | None = None) -> str:
    """Ruby Stdlib::Functions.reverse = String#reverse (WO19 G6)."""
    return text[::-1]


def strip(text: str, opts: dict | None = None) -> str:
    """Ruby Stdlib::Functions.strip = String#strip (WO19 G6)."""
    return text.strip(_RUBY_STRIP_SET)


def swapcase(text: str, opts: dict | None = None) -> str:
    """Ruby Stdlib::Functions.swapcase = String#swapcase (WO19 G6)."""
    return text.swapcase()


class Function(Protocol):
    def __call__(self, text: str, opts: dict | None = None) -> str: ...


BUILTIN_FUNCTIONS: dict[str, Function] = {
    "downcase": downcase,
    "upcase": upcase,
    "title_case": title_case,
    # WO19 G6: the three new fn literals execute as directives and
    # inline to-funcalls with the plain String semantics of ruby
    # Stdlib::Functions.
    "reverse": reverse,
    "strip": strip,
    "swapcase": swapcase,
    "separate": separate,
    # Reverse-mode counterpart of `separate` (Stdlib.reverse_function).
    "unseparate": unseparate,
    "compose": compose,
    "decompose": decompose,
}
