# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Grammar provenance pin — the embedded ISC grammar text must match the
sha256 recorded at sync time. A mismatch means grammar_source.py was
edited by hand instead of via scripts/sync_isc_grammar.py, or the sync
was run against a different interscript-ruby revision than the pin
records. Either way the drift must be deliberate, never silent.

(Mirror of interscript-ts's test/isc/grammar-source.test.ts — both
vendored copies must pin the same .parg text.)
"""

import hashlib

from interscript.grammar import isc_parser
from interscript.grammar.grammar_source import ISC_PARG_SHA256, ISC_PARG_SOURCE
from interscript.isc import parse_isc


class TestGrammarSourcePin:
    def test_matches_recorded_sha256(self):
        sha = hashlib.sha256(ISC_PARG_SOURCE.encode("utf-8")).hexdigest()
        assert sha == ISC_PARG_SHA256

    def test_declares_isc_entry_point(self):
        # A cheap structural sanity check alongside the hash pin.
        assert "entry isc: isc_source" in ISC_PARG_SOURCE
        assert 'grammar InterscriptIsc version "' in ISC_PARG_SOURCE

    def test_compiles_and_parses(self):
        doc = parse_isc('system "pin-test" { stage main { } }', "pin.isc")
        assert doc.system_code == "pin-test"

    def test_extension_targets_present_in_canonical_grammar(self):
        # The shape guard in compile_grammar duplicates this; pin it
        # independently so a renamed rule fails HERE with a clear message.
        grammar = isc_parser.parse_parg(ISC_PARG_SOURCE)
        for name in ("any_arg", "block_rule", "run_dep", "rule_items"):
            assert name in grammar.rules, f"GRAMMAR_EXTENSIONS target {name} missing"


class TestGeneratedParserPins:
    """The hand-parser behaviors the generated parser must keep (the
    error-message shapes the suite relies on)."""

    def test_unterminated_string_message(self):
        import pytest

        from interscript.errors import IscParseError

        with pytest.raises(IscParseError, match="Unterminated string"):
            parse_isc('system "s { stage main { } }', "t.isc")

    def test_keyword_in_item_position_message(self):
        import pytest

        from interscript.errors import IscParseError

        with pytest.raises(IscParseError, match="keyword"):
            parse_isc('system "s" { stage main { sub when "y" } }', "t.isc")

    def test_error_position_line(self):
        import pytest

        from interscript.errors import IscParseError

        with pytest.raises(IscParseError) as exc:
            parse_isc('system "s" {\n  bogus {\n}\n', "t.isc")
        assert exc.value.line == 2
