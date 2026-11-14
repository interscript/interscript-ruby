# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Stdlib tests: trie parallel replace, megaregexp, builtin functions."""

from __future__ import annotations

import regex

from interscript.stdlib import (
    BUILTIN_FUNCTIONS,
    MegaregexpRule,
    compile_parallel_tree,
    compose,
    decompose,
    downcase,
    parallel_megaregexp,
    parallel_replace,
    parallel_replace_tree,
    regexp_escape,
    separate,
    title_case,
    unseparate,
    upcase,
)


class TestParallelReplace:
    def test_simple_pairs(self):
        assert parallel_replace("abc", [("a", "x"), ("b", "y")]) == "xyc"

    def test_longest_match_wins(self):
        assert parallel_replace("abcd", [("ab", "1"), ("abcd", "Z")]) == "Z"
        assert parallel_replace("abx", [("ab", "1"), ("abcd", "Z")]) == "1x"

    def test_no_overlap_reapplication(self):
        # Replacements are never re-fed through the trie in the same pass.
        assert parallel_replace("ab", [("a", "b"), ("b", "c")]) == "bc"

    def test_empty_pairs_is_identity(self):
        assert parallel_replace("abc", []) == "abc"

    def test_multibyte(self):
        assert parallel_replace("нос Бяга", [("н", "n"), ("о", "o"), ("с", "s")]) == "nos Бяга"

    def test_tree_walk_matches_naive_reference(self):
        pairs = [("a", "1"), ("ab", "2"), ("bc", "3"), ("c", "4")]
        tree = compile_parallel_tree(pairs)

        def naive(s):
            out = ""
            i = 0
            while i < len(s):
                for src, dst in sorted(pairs, key=lambda p: -len(p[0])):
                    if s.startswith(src, i):
                        out += dst
                        i += len(src)
                        break
                else:
                    out += s[i]
                    i += 1
                continue
            return out

        for sample in ["abc", "aabbcc", "abcabc", "abcbc", "xyz", ""]:
            assert parallel_replace_tree(sample, tree) == naive(sample)


class TestMegaregexp:
    def test_first_alternative_wins_at_position(self):
        rules = [
            MegaregexpRule(pattern="ab", replace=lambda m, g: "1"),
            MegaregexpRule(pattern="a", replace=lambda m, g: "2"),
        ]
        assert parallel_megaregexp("ab", rules) == "1"

    def test_lookaround_constraints(self):
        rules = [
            MegaregexpRule(
                pattern="a(?=b)", replace=lambda m, g: "X"
            ),
            MegaregexpRule(pattern="a", replace=lambda m, g: "Y"),
        ]
        assert parallel_megaregexp("ab a", rules) == "Xb Y"

    def test_capture_template(self):
        def repl(m, groups):
            return f"<{groups[0]}>"

        rules = [MegaregexpRule(pattern="([0-9]+)", replace=repl)]
        assert parallel_megaregexp("a12b3", rules) == "a<12>b<3>"

    # WO18 G1 — the megaregexp join wraps each rule in a named group;
    # $N templates must resolve against the RULE's own capture list
    # (rs semantics), not the global list that includes the wrappers.

    def test_rule_gets_its_own_captures_not_the_wrapper_match(self):
        seen = []

        def repl(m, groups):
            seen.append(list(groups))
            return f"{groups[0]}X"

        rules = [
            MegaregexpRule(pattern="([a-z])x", replace=repl),
            MegaregexpRule(pattern="b", replace=lambda m, g: m.upper()),
        ]
        assert parallel_megaregexp("axb", rules) == "aXB"
        assert seen[0] == ["a"]

    def test_later_rule_captures_offset_past_earlier_inner_groups(self):
        rules = [
            MegaregexpRule(
                pattern="([a-z])x",
                replace=lambda m, g: f"{g[0]}X",
            ),
            MegaregexpRule(
                pattern="b([0-9])",
                replace=lambda m, g: g[0] if g[0] is not None else "?",
            ),
        ]
        # "ax" hits rule 0; "b5" hits rule 1, whose only capture is "5" —
        # the wrappers of rule 0 and rule 1 must not shift it.
        assert parallel_megaregexp("axb5", rules) == "aX5"

    def test_rule_local_numbering_with_two_captures(self):
        rules = [
            MegaregexpRule(
                pattern="([a-z])([0-9])",
                replace=lambda m, g: f"{g[1]}{g[0]}",
            )
        ]
        assert parallel_megaregexp("k3", rules) == "3k"


class TestFunctions:
    def test_case_functions(self):
        assert upcase("aβ") == "AΒ"
        assert downcase("AΒ") == "aβ"

    def test_title_case(self):
        assert title_case("hello world") == "Hello World"
        assert title_case(" mary-jane ", {"wordSeparator": "-"}) == " mary-Jane "

    def test_separate(self):
        assert separate("abc") == "a b c"
        assert separate("abc", {"separator": "-"}) == "a-b-c"

    def test_unseparate(self):
        assert unseparate("a b c") == "abc"
        assert unseparate("a-b-c", {"separator": "-"}) == "abc"
        assert unseparate("a  b") == "ab"

    def test_compose_decompose(self):
        composed = "ñ"
        decomposed = decompose(composed)
        assert decomposed == "ñ"
        assert compose(decomposed) == composed

    def test_registry_has_all_builtins(self):
        assert set(BUILTIN_FUNCTIONS) == {
            "downcase",
            "upcase",
            "title_case",
            "separate",
            "unseparate",
            "compose",
            "decompose",
        }


class TestRegexpEscape:
    def test_escapes_metacharacters(self):
        assert regexp_escape("a.b*c") == r"a\.b\*c"
        assert regexp_escape("(x)[y]{z}") == r"\(x\)\[y\]\{z\}"
        assert regexp_escape("no special") == "no special"

    def test_escaped_string_matches_literally(self):
        pattern = regex.compile(regexp_escape("a.b"), regex.VERSION0)
        assert pattern.fullmatch("a.b")
        assert not pattern.fullmatch("axb")
