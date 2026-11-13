# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Generated ISC parser — the parsanol grammar (grammar_source.py) drives a
table-driven PEG interpreter (parg_reader.py + peg.py) and the resulting
capture tree is lowered to an IscDocument by the action layer
(actions.py), which also runs the W1/W2 expansion (isc._Expander).

This module replaces the hand-written recursive-descent parser while
keeping its public API byte-compatible: `parse_isc(source, filename,
resolve_dependency)` returning an IscDocument and throwing IscParseError
on syntax errors.

Single-sourcing contract: the grammar TEXT embedded in grammar_source.py
is the semantic source of truth (synced from interscript-ruby's
lib/interscript/isc/grammar/isc.parg via scripts/sync_isc_grammar.py).
The four documented grammar-table extensions below (GRAMMAR_EXTENSIONS)
restore hand-parser behaviors the canonical .parg rejects — each is
spelled in the grammar language, named, and corpus-proven dormant.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from ..errors import IscParseError
from .actions import TreeToDocument
from .grammar_source import ISC_PARG_SOURCE
from .parg_reader import Alt, Lit, PargGrammar, parse_parg
from .peg import PegError, PegInterpreter

# The compact rule's from/to captures carry no delimiters in the capture
# tree (closing quotes are not captured) — but the W2 override key is the
# byte-exact source text of the from atom. The interpreter records the
# exact match spans for these two capture names; the action layer pairs
# them with the tree in walk order.
_SPAN_CAPTURES = frozenset({"from", "to"})

# The rules whose failures carry diagnostic state the error renderer
# below reads: "double_quoted" (Unterminated string) and "item_atom"
# (keyword-in-item-position). The interpreter keeps per-failure
# position tables for exactly these rules.
_DIAG_RULES = frozenset({"double_quoted", "item_atom"})

# extract [A-Za-z0-9_]* at a position (the hand parser's peek_word)
_WORD_RE = re.compile(r"[A-Za-z0-9_]*")


@dataclass
class CompiledGrammar:
    grammar: PargGrammar
    # rule name -> peg node (the merged table: canonical .parg + extensions)
    rules: dict
    entry: str
    # The keyword table, derived from the grammar itself (load-bearing for
    # the keyword-in-item-position diagnostic below — no drift).
    keywords: frozenset[str] = field(default_factory=frozenset)


_compiled: CompiledGrammar | None = None


def compile_grammar() -> CompiledGrammar:
    global _compiled
    if _compiled is not None:
        return _compiled

    grammar = parse_parg(ISC_PARG_SOURCE)
    rules = dict(grammar.rules)
    # Shape-guarded merge: if a future .parg edit renames any of the three
    # rules, the merge raises instead of silently misparsing.
    ext = parse_parg(GRAMMAR_EXTENSIONS)
    for name in ("any_arg", "block_rule", "run_dep", "rule_items"):
        if name not in rules or name not in ext.rules:
            raise RuntimeError(
                f"grammar extension target {name} missing from isc.parg — "
                f"recheck GRAMMAR_EXTENSIONS"
            )
        rules[name] = ext.rules[name]
    kw_rule = grammar.rules["keyword"]
    keywords = (
        frozenset(n.s for n in kw_rule.a if isinstance(n, Lit))
        if isinstance(kw_rule, Alt)
        else frozenset()
    )
    _compiled = CompiledGrammar(
        grammar=grammar,
        rules=rules,
        entry=grammar.entries.get("isc", "isc_source"),
        keywords=keywords,
    )
    return _compiled


def parse_isc(source, filename=None, resolve_dependency=None):
    """Parse ISC source text into an IscDocument.

        doc = parse_isc(source, "map.isc")

    Raises IscParseError (with filename/line/col, like the hand parser)
    on syntax errors.
    """
    c = compile_grammar()
    interp = PegInterpreter(c.rules, source, span_names=_SPAN_CAPTURES, diag_rules=_DIAG_RULES)
    try:
        tree, _end = interp.parse_root(c.entry)
    except PegError as e:
        message, at = _hand_style_failure(source, c, interp, e)
        at = max(min(at, max(len(source) - 1, 0)), 0)
        line = source.count("\n", 0, at) + 1
        col = at - source.rfind("\n", 0, at)
        full = f"{filename}: {message}" if filename else message
        raise IscParseError(full, at, line, col) from None
    return TreeToDocument(source, filename, resolve_dependency).run(tree, interp.spans)


def _hand_style_failure(source, c, interp, peg_error) -> tuple[str, int]:
    """Render a parse failure the way the replaced hand parser reported
    it. Two hand-parser messages are pinned by the suite and reproduced
    from real parse state; everything else gets the interpreter's
    deepest-failure report (the same contract as the hand parser's
    deepest-error reporting). Returns (message, position)."""
    if peg_error.at >= len(source) and "double_quoted" in interp.failed_rules:
        # A double-quoted literal ran past EOF (the hand parser's
        # parse_quoted_string reports this exact message).
        return "Unterminated string", peg_error.at
    # A keyword landed in item position: item_atom failed at a position
    # whose word is a grammar keyword — the hand parser's
    # parse_item_atom_raw guard, verbatim message and position. (The
    # interpreter's farthest-failure position cannot be used here: the
    # alias_decl_stop lookahead scans past the keyword first.)
    for pos in interp.failed_positions.get("item_atom", []):
        m = _WORD_RE.match(source, pos)
        word = m.group(0) if m else ""
        if word in c.keywords:
            return f"Unexpected keyword in item position: {word}", pos
    return peg_error.args[0], peg_error.at


GRAMMAR_EXTENSIONS = """
grammar IscExtensions version "0.0.0" {
  any_arg = range_arg / set_arg / alias_arg / ((item) as any_item)
  block_rule = ("sub" [ws] "{" [ws] "from" whitespace ((item) as from) [ws] "to" whitespace ((item) as to) ((*(whitespace constraint)) as constraints) [ws] "}" [(when_guard)]) / ("sub" [ws] "{" [ws] "from" whitespace ((item) as from) [ws] "to" whitespace ((item) as to) ((*(whitespace constraint)) as constraints) [(when_guard)] [ws] "}")
  run_dep = "map." (((identifier *("-" identifier)) / identifier) as dep) ".stage." (identifier as stage)
  rule_items = *(([ws] ((use_directive / rule / comment_item)) [ws]))
}
"""

# GRAMMAR_EXTENSIONS — the places where the former hand parser accepted
# syntax the canonical .parg rejects. Each is spelled in the grammar
# language itself and merged into the rule table, so the .parg remains
# the only semantic source and every extension is one visible, named
# block (the first three are the same extensions the ts generated
# parser ships):
#
# 1. `any_arg` — restore the ruby DSL's final `item as :any_item`
#    fallback (concerns/items.rb any_constructor), which the canonical
#    .parg dropped; the interscript-rs vendored copy keeps it.
#    (`any(space)`, `any(space + line_end)` — the ts suite pins both.)
# 2. `block_rule` — accept the `when` guard AFTER the closing brace of
#    the block form. The ruby DSL places the guard inside the braces;
#    the ts and py runtimes both place it outside, and the py suite pins
#    the outside form (test_isc_parser.py::test_when_suffix_after_block_form).
#    The outside branch is tried first (it is the greedy one; its
#    mandatory `}` keeps it from shadowing the inside form).
# 3. `run_dep` — allow hyphenated dependency names (`run map.some-dep.…`).
#    The grammar's identifier is [A-Za-z_][A-Za-z0-9_]*; the former hand
#    parser's identifier admitted `-` in structural positions. Only the
#    dependency slot is widened; the corpus is hyphen-free in every
#    identifier position (proven by the corpus parity driver).
# 4. `rule_items` — accept `use` directives inside parallel/sequence
#    blocks (ISC-WF-1 §3: a ruleset can be spliced into one pass). The
#    canonical .parg only feeds rule_line (sub-rows/comments) to pass
#    blocks; the hand parser accepted `use` there and the py suite pins
#    it (test_isc_parser.py::test_use_inside_parallel_participates_in_pass).
#    `use` shadows nothing in rule position (rule always starts with
#    "sub", comment with "#"). The override block's rule_line is left
#    canonical — the hand parser silently DROPPED non-sub rows there,
#    so a `use` inside `override {}` is a generated-parser rejection of
#    a construct the corpus never uses.
#
# Ruby rejects (1)'s absence aside, the outside-when, hyphen-dep, and
# use-in-pass forms are cross-runtime divergences (ruby parses none);
# aligning ruby/ts/py on one placement is an owner decision. None of the
# four extensions fires on any corpus map (proven: the corpus py-vs-py
# document-diff driver passes byte-identical with them in place, and a
# corpus-wide scan finds no `use` inside a pass block).
