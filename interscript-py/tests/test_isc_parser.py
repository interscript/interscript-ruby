# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""ISC parser unit tests — one class per construct (ISC-WF-1 §6.1).

Covers the base grammar surface the py runtime needs (metadata, tests,
aliases, dependency, stage items, rules, items) plus the four WF-1
constructs: ruleset (W1), use with override (W2), languages/when (W3
parse side — executor semantics live in test_isc_wf1.py).
"""

from __future__ import annotations

import pytest

from interscript._ir_types import (
    FuncallInline,
    FuncallRule,
    StringItem,
    SubRule,
)
from interscript.errors import IscLoadError, IscParseError
from interscript.executor import execute_stage
from interscript.isc import (
    IscDocument,
    ParallelBlock,
    ParsedRule,
    SequenceBlock,
    isc_to_compiled_map,
    parse_isc,
)


def parse(src: str, **kw) -> IscDocument:
    return parse_isc(src, "test.isc", **kw)


def bare_rules(doc: IscDocument, stage: str = "main") -> list[SubRule]:
    """Expanded stage items flattened to (kind, from, to, when) tuples."""
    out = []
    st = next(s for s in doc.stages if s.name == stage)
    for item in st.items:
        if isinstance(item, ParallelBlock):
            out.extend(item.rules)
        elif isinstance(item, ParsedRule):
            out.append(item)
    return out


def row(r: ParsedRule) -> tuple[str | None, str | None, tuple[str, ...] | None]:
    f = r.rule.from_
    t = r.rule.to
    return (
        f.value if isinstance(f, StringItem) else None,
        t.value if isinstance(t, StringItem) else None,
        r.rule.when,
    )


class TestBaseGrammar:
    def test_minimal_document(self):
        doc = parse('system "ISO:rus-Cyrl:Latn:9-1995" { stage main { } }')
        assert doc.system_code == "ISO:rus-Cyrl:Latn:9-1995"
        assert doc.languages is None
        assert [s.name for s in doc.stages] == ["main"]

    def test_metadata_description_notes_generic(self):
        src = '''
system "s" {
  metadata {
    authority_id iso
    description {
      A long description
      over two lines
    }
    notes {
      note "first note"
      note "second note"
    }
    name Romanization Table
  }
}
'''
        doc = parse(src)
        md = doc.metadata
        assert md["authority_id"] == "iso"
        assert "over two lines" in md["description"]
        assert md["notes"] == ["first note", "second note"]
        assert md["name"] == "Romanization Table"

    def test_notes_raw_text_form(self):
        doc = parse('system "s" { metadata { notes { free text here } } }')
        assert doc.metadata["notes"] == "free text here"

    def test_tests_block(self):
        src = '''
system "s" {
  tests {
    # a comment
    "а" -> "a"
    "б" -> "b" note "why"
  }
}
'''
        doc = parse(src)
        assert [(t.input, t.expected) for t in doc.tests] == [("а", "a"), ("б", "b")]
        assert doc.tests[1].note == "why"

    def test_aliases_block(self):
        doc = parse('system "s" { aliases { vowels = any("ae") } stage main { } }')
        assert "vowels" in dict(doc.aliases)

    def test_dependency_with_alias(self):
        doc = parse(
            'system "s" { dependency "iso-9-base" as base9  stage main { } }'
        )
        assert doc.dependencies[0].target == "iso-9-base"
        assert doc.dependencies[0].alias_name == "base9"

    def test_dependency_without_alias(self):
        doc = parse('system "s" { dependency "posix"  stage main { } }')
        assert doc.dependencies[0].target == "posix"
        assert doc.dependencies[0].alias_name is None

    def test_compact_rule_constraints(self):
        doc = parse('system "s" { stage main { sub "a" "b" before "c" not_after "d" } }')
        rule = bare_rules(doc)[0].rule
        assert rule.before == StringItem(value="c")
        assert rule.not_after == StringItem(value="d")

    def test_block_rule_form(self):
        doc = parse(
            'system "s" { stage main { sub { from "a" to upcase before "x" } } }'
        )
        rule = bare_rules(doc)[0].rule
        assert rule.from_ == StringItem(value="a")
        assert rule.to == FuncallInline(name="upcase")
        assert rule.before == StringItem(value="x")

    def test_parallel_and_sequence_blocks(self):
        doc = parse(
            'system "s" { stage main { parallel { sub "a" "b" } sequence { sub "c" "d" } } }'
        )
        st = doc.stages[0]
        assert isinstance(st.items[0], ParallelBlock)
        assert isinstance(st.items[1], SequenceBlock)

    def test_run_and_funcall_items(self):
        src = '''
system "s" {
  dependency "dep-map" as d
  stage main {
    run stage.other
    run map.d.stage.main
    upcase
    separate separator "-"
    compose
  }
}
'''
        doc = parse(src)
        items = doc.stages[0].items
        assert items[0].stage == "other" and items[0].dependency is None
        assert items[1].dependency == "d" and items[1].stage == "main"
        assert isinstance(items[2], FuncallRule) and items[2].name == "upcase"
        assert items[3].kwargs == {"separator": "-"}
        assert items[4].name == "compose"

    def test_unterminated_string_error(self):
        with pytest.raises(IscParseError, match="Unterminated string"):
            parse('system "s { stage main { } }')

    def test_parse_error_has_position(self):
        with pytest.raises(IscParseError) as exc:
            parse('system "s" {\n  bogus {\n}\n')
        assert exc.value.line == 2


class TestW3ParseSide:
    def test_languages_declaration(self):
        doc = parse(
            'system "s" {\n  languages rus bel ukr\n  stage main { }\n}'
        )
        assert doc.languages == ("rus", "bel", "ukr")

    def test_languages_comma_form(self):
        doc = parse('system "s" { languages kur, ckv  stage main { } }')
        assert doc.languages == ("kur", "ckv")

    def test_languages_duplicate_declaration_error(self):
        with pytest.raises(IscParseError, match="more than once"):
            parse('system "s" { languages a  languages b  stage main { } }')

    def test_languages_declaration_on_one_line(self):
        doc = parse('system "s" { languages kur stage main { } }')
        assert doc.languages == ("kur",)
        assert [s.name for s in doc.stages] == ["main"]

    def test_when_suffix_compact_form(self):
        doc = parse(
            'system "s" { languages kur ckv  stage main { sub "қ" "k" when kur, ckv } }'
        )
        assert row(bare_rules(doc)[0]) == ("қ", "k", ("kur", "ckv"))

    def test_when_suffix_space_separated(self):
        doc = parse('system "s" { stage main { sub "қ" "k" when kur ckv } }')
        assert row(bare_rules(doc)[0])[2] == ("kur", "ckv")

    def test_when_list_does_not_swallow_next_rule(self):
        doc = parse(
            'system "s" { stage main { sub "x" "y" when kur  sub "z" "w" } }'
        )
        rows = [row(r) for r in bare_rules(doc)]
        assert rows == [("x", "y", ("kur",)), ("z", "w", None)]

    def test_when_inside_block_form(self):
        # WO19 G6 item 5: canonical rs binds the when guard inside the
        # braces; ruby parses the inside form only. The former py/ts
        # outside-form extension (`} when kur`) is retired.
        doc = parse(
            'system "s" { stage main { sub { from "x" to "y" when kur } } }'
        )
        assert row(bare_rules(doc)[0]) == ("x", "y", ("kur",))

    def test_when_suffix_after_block_form_rejected(self):
        # WO19 G6 item 5: the outside form is no longer accepted (the
        # block_rule extension was retired with the alignment).
        with pytest.raises(IscParseError):
            parse(
                'system "s" { stage main { sub { from "x" to "y" } when kur } }'
            )

    def test_capital_u_escape_decodes(self):
        # WO19 G6 item 4 (the gki-bel shape): `sub "\U040E" "Ŭ"` — the
        # former hand parser carried the from as the literal text
        # "U040E" and the row never fired. Both spellings decode now
        # (ruby/rs always did).
        doc = parse('system "s" { stage main { sub "\\U040E" "Ŭ" } }')
        assert row(bare_rules(doc)[0]) == ("Ў", "Ŭ", None)

    def test_keyword_alias_declaration_parses(self):
        # WO19 G6 item 1: the six fn names are reserved — a bare name is
        # never an alias reference — but `downcase = any(...)` still
        # DECLARES an alias named downcase (alias_decl has no keyword
        # guard).
        doc = parse(
            'system "s" { aliases { downcase = any("a".."z") } stage main { sub "k" "K" } }'
        )
        assert row(bare_rules(doc)[0]) == ("k", "K", None)

    def test_when_is_not_parsed_as_to(self):
        # §2: `when` joins the keyword table — `sub "x" when kur` must not
        # read `when` as the replacement string.
        doc = parse('system "s" { stage main { sub "x" "y" when kur } }')
        assert row(bare_rules(doc)[0]) == ("x", "y", ("kur",))

    def test_when_never_an_alias_reference(self):
        with pytest.raises(IscParseError, match="keyword"):
            parse('system "s" { stage main { sub when "y" } }')

    def test_keywords_inside_strings_untouched(self):
        doc = parse(
            'system "s" { stage main { sub "use when override languages ruleset" "y" } }'
        )
        assert row(bare_rules(doc)[0])[0] == "use when override languages ruleset"

    def test_prose_with_keywords_in_metadata(self):
        doc = parse(
            'system "s" { metadata { note "ruleset when languages use override appear in prose" } }'
        )
        assert "ruleset" in doc.metadata["note"]


class TestW1Rulesets:
    def test_ruleset_is_not_a_stage(self):
        doc = parse(
            'system "s" { ruleset tbl { sub "a" "b" } stage main { use tbl } }'
        )
        assert [s.name for s in doc.stages] == ["main"]
        assert "tbl" in doc.rulesets

    def test_library_map_rulesets_only(self):
        doc = parse('system "shared" { ruleset tbl { sub "a" "b" } }')
        assert doc.stages == ()
        assert list(doc.rulesets) == ["tbl"]

    def test_use_expands_in_place_in_document_order(self):
        doc = parse(
            'system "s" { ruleset tbl { sub "a" "A" } '
            'stage main { sub "1" "!" use tbl sub "2" "@" } }'
        )
        rows = [row(r)[:2] for r in bare_rules(doc)]
        assert rows == [("1", "!"), ("a", "A"), ("2", "@")]

    def test_use_inside_parallel_participates_in_pass(self):
        doc = parse(
            'system "s" { ruleset tbl { sub "bc" "Z" } '
            'stage main { parallel { use tbl sub "abc" "Q" } } }'
        )
        cm = isc_to_compiled_map(doc)
        # one simultaneous pass: abc wins over bc
        assert execute_stage(cm, "main", "xabc") == "xQ"

    def test_ruleset_with_parallel_block_is_one_pass_at_position(self):
        doc = parse(
            'system "s" { ruleset tbl { parallel { sub "ab" "X" } } '
            'stage main { sub "k" "ab" use tbl } }'
        )
        cm = isc_to_compiled_map(doc)
        # the bare rule runs first (document order); the expanded block
        # is one pass at its position
        assert execute_stage(cm, "main", "k") == "X"

    def test_recursive_expansion(self):
        doc = parse(
            'system "s" { ruleset outer { use inner  sub "z" "Z" } '
            'ruleset inner { sub "a" "A" } '
            'stage main { use outer } }'
        )
        rows = [row(r)[:2] for r in bare_rules(doc)]
        assert rows == [("a", "A"), ("z", "Z")]

    def test_forward_reference(self):
        doc = parse(
            'system "s" { stage main { use later } ruleset later { sub "a" "A" } }'
        )
        assert row(bare_rules(doc)[0])[:2] == ("a", "A")

    def test_cycle_error(self):
        with pytest.raises(IscLoadError, match="use cycle"):
            parse(
                'system "s" { ruleset a { use b } ruleset b { use a } '
                'stage main { use a } }'
            )

    def test_self_cycle_error(self):
        with pytest.raises(IscLoadError, match="use cycle"):
            parse('system "s" { ruleset a { use a } stage main { use a } }')

    def test_unknown_ruleset_error(self):
        with pytest.raises(IscLoadError, match="unknown ruleset"):
            parse('system "s" { stage main { use nope } }')

    # WO18 G5 — §3.2: items inside a pass block participate in that
    # block's single pass; a ruleset containing a parallel block
    # contributes that block as one pass at the expansion position.
    # The expansion flattens the referenced ruleset's rules into the
    # enclosing collection; non-rule targets are a named load error.

    def test_use_in_sequence_flattens_in_position(self):
        # mirrors maps probe tst-use-inseq (rs expects "12")
        doc = parse(
            'system "T:tst-use-inseq:1" { ruleset r1 { parallel { sub "a" "1" } } '
            'stage main { sequence { use r1  sub "b" "2" } } }'
        )
        cm = isc_to_compiled_map(doc)
        assert execute_stage(cm, "main", "ab") == "12"

    def test_use_in_parallel_joins_the_pass(self):
        doc = parse(
            'system "T:tst-use-inpar:1" { ruleset r1 { parallel { sub "a" "1" } } '
            'stage main { parallel { use r1  sub "b" "2" } } }'
        )
        cm = isc_to_compiled_map(doc)
        # one simultaneous pass: a→1 and b→2 together
        assert execute_stage(cm, "main", "ab") == "12"

    def test_ruleset_with_parallel_block_is_one_pass_in_sequence(self):
        doc = parse(
            'system "s" { ruleset tbl { parallel { sub "a" "b" } sub "c" "d" } '
            'stage main { sequence { use tbl  sub "e" "E" } } }'
        )
        # the used ruleset's rules splice flat, in position (spec §3.2)
        seq = doc.stages[0].items[0]
        assert [row(r)[:2] for r in seq.rules] == [("a", "b"), ("c", "d"), ("e", "E")]

    def test_override_in_block_merges_per_rule(self):
        doc = parse(
            'system "s" { ruleset tbl { parallel { sub "a" "A1"  sub "b" "B" } } '
            'stage main { parallel { use tbl override { sub "a" "A2" } } } }'
        )
        cm = isc_to_compiled_map(doc)
        # child-wins replacement on the flat row list, all inside one pass
        assert execute_stage(cm, "main", "xa xb") == "xA2 xB"

    def test_non_rule_target_in_block_is_named_error(self):
        with pytest.raises(IscLoadError, match="cannot join the pass"):
            parse(
                'system "s" { ruleset tbl { sub "a" "A"  upcase } '
                'stage main { parallel { use tbl } } }'
            )

    def test_non_rule_target_through_nested_use_is_named_error(self):
        # the funcall sits in the indirectly referenced ruleset; the
        # flattening reaches it through one use-of-a-use hop
        with pytest.raises(IscLoadError, match="cannot join the pass"):
            parse(
                'system "s" { ruleset tbl { sub "a" "A"  upcase } '
                'ruleset wrap { use tbl } '
                'stage main { sequence { use wrap } } }'
            )

    def test_cross_dependency_use(self):
        base = parse('system "base" { ruleset tbl { sub "a" "A" sub "b" "B" } }')
        doc = parse(
            'system "kid" { dependency "base" as b9 '
            'stage main { use b9.tbl } }',
            resolve_dependency=lambda code: base if code == "base" else None,
        )
        rows = [row(r)[:2] for r in bare_rules(doc)]
        assert rows == [("a", "A"), ("b", "B")]

    def test_unknown_dependency_alias(self):
        with pytest.raises(IscLoadError, match="unknown dependency alias"):
            parse('system "s" { stage main { use ghost.tbl } }')

    def test_unresolvable_dependency(self):
        with pytest.raises(IscLoadError, match="cannot resolve dependency"):
            parse(
                'system "s" { dependency "missing" as m  stage main { use m.tbl } }',
                resolve_dependency=lambda code: None,
            )

    def test_no_resolver(self):
        with pytest.raises(IscLoadError, match="no resolver"):
            parse('system "s" { dependency "d" as m  stage main { use m.tbl } }')

    def test_missing_ruleset_in_dependency(self):
        base = parse('system "base" { ruleset other { sub "a" "A" } }')
        with pytest.raises(IscLoadError, match="unknown ruleset in dependency"):
            parse(
                'system "s" { dependency "base" as b  stage main { use b.tbl } }',
                resolve_dependency=lambda code: base,
            )


class TestW2Override:
    def test_child_wins_on_exact_from_equality(self):
        doc = parse(
            'system "s" { ruleset tbl { sub "ะ" "e"  sub "ั" "a" } '
            'stage main { use tbl override { sub "ะ" "a2011" } } }'
        )
        rows = [row(r)[:2] for r in bare_rules(doc)]
        # R_kept in R's order, then O in O's order (§4.2 rule 2)
        assert rows == [("ั", "a"), ("ะ", "a2011")]

    def test_all_same_from_rows_replaced(self):
        doc = parse(
            'system "s" { ruleset tbl { sub "k" "k1" before "a"  sub "k" "k2" before "b"  sub "m" "M" } '
            'stage main { use tbl override { sub "k" "K" } } }'
        )
        rows = [row(r)[:2] for r in bare_rules(doc)]
        assert rows == [("m", "M"), ("k", "K")]

    def test_unmatched_overrides_added_at_end(self):
        doc = parse(
            'system "s" { ruleset tbl { sub "a" "A" } '
            'stage main { use tbl override { sub "x" "X" sub "a" "A2" } } }'
        )
        rows = [row(r)[:2] for r in bare_rules(doc)]
        # R_kept (empty — "a" was replaced) then O in O's order (§4.2 rules 2+4)
        assert rows == [("x", "X"), ("a", "A2")]

    def test_override_is_a_complete_row(self):
        # §4.2 rule 3: the override replaces the imported row's to value
        # AND its constraints.
        doc = parse(
            'system "s" { ruleset tbl { sub "k" "K1" before "v" } '
            'stage main { use tbl override { sub "k" "K2" } } }'
        )
        rule = bare_rules(doc)[0].rule
        assert rule.before is None
        assert rule.to == StringItem(value="K2")

    def test_override_row_carries_when(self):
        doc = parse(
            'system "s" { languages kur  ruleset tbl { sub "қ" "ķ" } '
            'stage main { use tbl override { sub "қ" "k" when kur } } }'
        )
        assert row(bare_rules(doc)[0]) == ("қ", "k", ("kur",))

    def test_override_inside_block_appends_at_block_end(self):
        doc = parse(
            'system "s" { ruleset tbl { parallel { sub "a" "A1"  sub "b" "B" } } '
            'stage main { use tbl override { sub "a" "A2" } } }'
        )
        block = doc.stages[0].items[0]
        rows = [row(r)[:2] for r in block.rules]
        # the replaced row's override joins the same pass, at its end
        assert rows == [("b", "B"), ("a", "A2")]

    def test_override_key_is_byte_exact(self):
        doc = parse(
            'system "s" { ruleset tbl { sub "а" "a"  sub "áb" "z" } '
            'stage main { use tbl override { sub "ab" "AB" } } }'
        )
        rows = [row(r)[:2] for r in bare_rules(doc)]
        # "ab" matches nothing ("а" is Cyrillic; "áb" differs) — added at end
        assert rows == [("а", "a"), ("áb", "z"), ("ab", "AB")]

    def test_duplicate_ruleset_declaration_error(self):
        with pytest.raises(IscParseError, match="more than once"):
            parse(
                'system "s" { ruleset t { sub "a" "b" } ruleset t { sub "c" "d" } '
                'stage main { use t } }'
            )
