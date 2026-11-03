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
    callback can tell which rule matched; the group also shifts inner
    capture numbering exactly as in the TS/Ruby engines, so `$1`
    templates resolve against the same global group list.
    """
    if not rules:
        return text
    parts = [f"(?P<__r{i}>{r.pattern})" for i, r in enumerate(rules)]
    mega = regex.compile("|".join(parts), REGEX_FLAGS)
    n_groups = mega.groups

    def _sub(m: regex.Match) -> str:
        for i, rule in enumerate(rules):
            if m.group(f"__r{i}") is not None:
                captures = [m.group(k) for k in range(1, n_groups + 1)]
                return rule.replace(m.group(0), captures)
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
    sep = (opts or {}).get("wordSeparator", " ")
    if sep == "":
        return text[:1].upper() + text[1:].lower()
    return sep.join(
        w[:1].upper() + w[1:].lower() if w else w for w in text.split(sep)
    )


def separate(text: str, opts: dict | None = None) -> str:
    sep = (opts or {}).get("separator", " ")
    return sep.join(text)


def compose(text: str, opts: dict | None = None) -> str:
    import unicodedata

    return unicodedata.normalize("NFC", text)


def decompose(text: str, opts: dict | None = None) -> str:
    import unicodedata

    return unicodedata.normalize("NFD", text)


class Function(Protocol):
    def __call__(self, text: str, opts: dict | None = None) -> str: ...


BUILTIN_FUNCTIONS: dict[str, Function] = {
    "downcase": downcase,
    "upcase": upcase,
    "title_case": title_case,
    "separate": separate,
    "compose": compose,
    "decompose": decompose,
}
