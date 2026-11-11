# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""ISC-WF-1 end-to-end tests.

Three layers:

- **Executor guard semantics** (W3, spec §5) on synthetic CompiledMaps:
  inert guards, guard-applicable beats unguarded same-from (parallel
  tree + megaregexp), sequence skips inert guards, run carries the
  selection into the dependency map's own declaration.
- **Additive JSON-IR decode**: `languages` on the document and `when`
  arrays on rules (the only two IR extensions; the TypeScript converter
  expands W1/W2 at build time).
- **Synthetic .isc fixtures through the full path**: base ruleset +
  dependent override across a declared dependency, and a
  language-conditioned table exercised with and without a selection,
  including the public `transliterate(..., language=...)` API.
"""

from __future__ import annotations

import json

import pytest

from interscript._ir_types import (
    CompiledMap,
    ParallelRule,
    RunRule,
    SequentialRule,
    Stage,
    StringItem,
    SubRule,
)
from interscript.executor import execute_stage
from interscript.isc import isc_to_compiled_map, parse_isc


def make_map(
    stages,
    aliases=None,
    dependencies=(),
    system_code="test-map",
    languages=None,
):
    return CompiledMap(
        schema_version=1,
        system_code=system_code,
        dependencies=tuple(dependencies),
        stages=tuple(stages),
        aliases=dict(aliases or {}),
        functions={},
        languages=tuple(languages) if languages else None,
    )


def sub(src, dst, when=None, **kw):
    return SubRule(
        from_=StringItem(value=src) if isinstance(src, str) else src,
        to=StringItem(value=dst) if isinstance(dst, str) else dst,
        when=tuple(when) if when else None,
        **kw,
    )


def stage(name, rules):
    return Stage(name=name, rules=tuple(rules))


class TestGuardFiltering:
    def test_no_selection_all_guards_inert(self):
        rules = [
            sub("қ", "ķ"),
            sub("қ", "K", when=("kur",)),
            sub("ҫ", "ş"),
            sub("ҫ", "S", when=("chv",)),
        ]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])], languages=("kur", "chv"))
        assert execute_stage(m, "main", "қ ҫ") == "ķ ş"

    def test_selected_guard_applies(self):
        rules = [
            sub("қ", "ķ"),
            sub("қ", "K", when=("kur",)),
            sub("ҫ", "ş"),
            sub("ҫ", "S", when=("chv",)),
        ]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])], languages=("kur", "chv"))
        assert execute_stage(m, "main", "қ ҫ", language="kur") == "K ş"
        assert execute_stage(m, "main", "қ ҫ", language="chv") == "ķ S"

    def test_undeclared_selection_inert(self):
        # §5.1: a selection outside the map's `languages` declaration
        # makes every guard inert (identical to no selection).
        rules = [sub("қ", "ķ"), sub("қ", "K", when=("kur",))]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])], languages=("kur",))
        assert execute_stage(m, "main", "қ", language="chv") == "ķ"

    def test_no_declaration_selection_inert(self):
        rules = [sub("қ", "ķ"), sub("қ", "K", when=("kur",))]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])])
        assert execute_stage(m, "main", "қ", language="kur") == "ķ"

    def test_guard_beats_unguarded_same_from_tree_mode(self):
        # §5.2 precedence: guard-applicable wins over the unguarded
        # same-from row without restating it, and regardless of order.
        for order in ("generic_first", "generic_last"):
            generic_first = order == "generic_first"
            rules = [
                sub("қ", "ķ"),
                sub("қ", "K", when=("kur",)),
            ] if generic_first else [
                sub("қ", "K", when=("kur",)),
                sub("қ", "ķ"),
            ]
            m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])], languages=("kur",))
            assert execute_stage(m, "main", "ққ", language="kur") == "KK"

    def test_guard_beats_unguarded_same_from_megaregexp(self):
        rules = [
            sub("қ", "ķ", before=StringItem(value="#")),
            sub("қ", "K", when=("kur",)),
        ]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])], languages=("kur",))
        # the constrained generic row loses to the guard even on "#" context
        assert execute_stage(m, "main", "#қ", language="kur") == "#K"

    def test_guard_literal_expansion_shadows_shared_literals(self):
        # any("а","б") expands to literals а,б: the guard shadows BOTH
        # shared literals but leaves unshared strings untouched.
        from interscript._ir_types import AnyItem

        rules = [
            sub(AnyItem(of=(StringItem(value="а"), StringItem(value="б"))), "X"),
            sub("а", "A", when=("kur",)),
        ]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])], languages=("kur",))
        assert execute_stage(m, "main", "абв", language="kur") == "AXв"

    def test_sequence_inert_guard_skipped(self):
        rules = [
            sub("a", "A"),
            sub("x", "X", when=("kur",)),
            sub("b", "B", when=("kur",)),
        ]
        m = make_map([stage("main", [SequentialRule(rules=tuple(rules))])], languages=("kur",))
        assert execute_stage(m, "main", "axb") == "Axb"

    def test_sequence_guard_applies_in_order(self):
        rules = [
            sub("1", "a"),
            sub("a", "B", when=("kur",)),
        ]
        m = make_map([stage("main", [SequentialRule(rules=tuple(rules))])], languages=("kur",))
        # sequences apply their rules in order; the guard row runs on the
        # output of the previous one
        assert execute_stage(m, "main", "1", language="kur") == "B"
        assert execute_stage(m, "main", "1") == "a"

    def test_bare_guarded_rule(self):
        # bare stage rules apply in sequence order; an inert guard is skipped
        m = make_map(
            [
                stage("main", [sub("a", "A"), sub("b", "B", when=("kur",))]),
            ],
            languages=("kur",),
        )
        assert execute_stage(m, "main", "ab") == "Ab"
        assert execute_stage(m, "main", "ab", language="kur") == "AB"

    def test_selection_carries_into_run_dependency(self):
        dep = make_map(
            [
                stage(
                    "main",
                    [ParallelRule(rules=(sub("x", "X"), sub("x", "Y", when=("kur",))))],
                )
            ],
            system_code="dep-map",
            languages=("kur",),
        )
        loader = type("L", (), {"load": staticmethod(lambda code: dep)})()
        m = make_map(
            [
                stage(
                    "main",
                    [RunRule(stage="main", doc_name="dep-map")],
                )
            ],
            languages=("kur",),
        )
        # the selection flows through the run rule; the dependency's own
        # declared languages validate it, and the guard beats the
        # unguarded same-from row inside the dependency's pass
        assert execute_stage(m, "main", "x", loader, "kur") == "Y"
        assert execute_stage(m, "main", "x", loader) == "X"

    def test_inert_vs_selected_identical_row_shapes(self):
        # §6.5: inertness is all-or-nothing — a non-matching selection
        # never partially applies.
        rules = [
            sub("s", "1", when=("ckv",)),
            sub("t", "2", when=("kur",)),
        ]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])], languages=("kur", "ckv"))
        assert execute_stage(m, "main", "st") == "st"
        assert execute_stage(m, "main", "st", language="kur") == "s2"
        assert execute_stage(m, "main", "st", language="ckv") == "1t"


class TestIrDecode:
    def test_decode_languages_and_when(self):
        doc = {
            "schemaVersion": 1,
            "systemCode": "ISO:rus-Cyrl:Latn:9-1995",
            "dependencies": [],
            "languages": ["kur", "ckv"],
            "stages": [
                {
                    "name": "main",
                    "rules": [
                        {
                            "kind": "parallel",
                            "rules": [
                                {
                                    "kind": "sub",
                                    "from": {"kind": "string", "value": "қ"},
                                    "to": {"kind": "string", "value": "k"},
                                    "when": ["kur"],
                                },
                                {
                                    "kind": "sub",
                                    "from": {"kind": "string", "value": "ҫ"},
                                    "to": {"kind": "string", "value": "s"},
                                },
                            ],
                        }
                    ],
                }
            ],
            "aliases": {},
            "functions": {},
        }
        m = CompiledMap.__new__(CompiledMap)
        from interscript._ir_types import map_from_json

        m = map_from_json(doc)
        assert m.languages == ("kur", "ckv")
        par = m.stages[0].rules[0]
        assert par.rules[0].when == ("kur",)
        assert par.rules[1].when is None

    def test_decode_without_new_fields_unchanged(self):
        doc = {
            "schemaVersion": 1,
            "systemCode": "x",
            "dependencies": [],
            "stages": [
                {
                    "name": "main",
                    "rules": [
                        {
                            "kind": "sub",
                            "from": {"kind": "string", "value": "a"},
                            "to": {"kind": "string", "value": "b"},
                        }
                    ],
                }
            ],
            "aliases": {},
            "functions": {},
        }
        from interscript._ir_types import map_from_json

        m = map_from_json(doc)
        assert m.languages is None
        assert m.stages[0].rules[0].when is None

    def test_artifact_corpus_has_no_new_fields(self):
        # Additivity today: no bundled corpus map carries the new fields.
        import os

        maps_dir = os.path.join(os.path.dirname(__file__), "data", "maps-ir", "maps")
        for name in sorted(os.listdir(maps_dir))[:50]:
            with open(os.path.join(maps_dir, name), encoding="utf-8") as fh:
                doc = json.load(fh)
            assert "languages" not in doc, name
            for st in doc["stages"]:
                for r in st["rules"]:
                    assert "when" not in r, name


# ---------------------------------------------------------------------------
# Synthetic .isc fixtures through the full path
# ---------------------------------------------------------------------------

BASE_ISC = """
system "ALALC:xxx-shared" {
  ruleset leading_vowels {
    sub "ะ" "e"
    sub "ั" "a"
    sub "ก" "k"
  }
}
"""

DEPENDENT_ISC = """
system "ALALC:xxx-Thai:Latn:2011" {
  dependency "ALALC:xxx-shared" as shared

  tests {
    "ะกั" -> "a2011ka"
  }

  stage main {
    use shared.leading_vowels override {
      sub "ะ" "a2011"
    }
    parallel {
      sub "ง" "ng"
    }
  }
}
"""


class TestFixtureOverrideAcrossDependency:
    @pytest.fixture()
    def maps(self):
        base = parse_isc(BASE_ISC, "shared.isc")
        docs = {"ALALC:xxx-shared": base}
        dependent = parse_isc(
            DEPENDENT_ISC,
            "dependent.isc",
            resolve_dependency=docs.get,
        )
        return base, dependent

    def test_base_ruleset_expands_alone(self, maps):
        base, _ = maps
        # a ruleset-only map is a library: no stages, no self-execution
        assert base.stages == ()
        lib = parse_isc(
            'system "L" { ruleset l { sub "ะ" "e" sub "ั" "a" sub "ก" "k" } '
            'stage main { use l } }'
        )
        cm = isc_to_compiled_map(lib)
        from interscript.executor import execute_stage

        assert execute_stage(cm, "main", "ะกั") == "eka"

    def test_dependent_override_via_dependency(self, maps):
        _, dependent = maps
        assert dependent.dependencies[0].target == "ALALC:xxx-shared"
        cm = isc_to_compiled_map(dependent)
        from interscript.executor import execute_stage

        # child-wins: the 2011 override replaces the shared row's value
        assert execute_stage(cm, "main", "ะกั") == "a2011ka"

    def test_embedded_tests_replay(self, maps):
        _, dependent = maps
        cm = isc_to_compiled_map(dependent)
        from interscript.executor import execute_stage

        for t in dependent.tests:
            assert execute_stage(cm, "main", t.input) == t.expected

    def test_dependency_ruleset_used_without_override(self, maps):
        base, _ = maps
        src = """
system "ALALC:xxx-plain" {
  dependency "ALALC:xxx-shared" as shared
  stage main {
    use shared.leading_vowels
  }
}
"""
        doc = parse_isc(src, resolve_dependency={"ALALC:xxx-shared": base}.get)
        cm = isc_to_compiled_map(doc)
        from interscript.executor import execute_stage

        assert execute_stage(cm, "main", "ะกั") == "eka"


LANGUAGE_ISC = """
system "ISO:xxx-9-1995" {
  languages kur ckv

  tests {
    "қҫ" -> "ķş"
  }

  stage main {
    parallel {
      sub "қ" "ķ"
      sub "қ" "k" when kur
      sub "ҫ" "ş"
      sub "ҫ" "s" when ckv
    }
  }
}
"""


class TestFixtureLanguageConditioned:
    @pytest.fixture()
    def compiled(self):
        doc = parse_isc(LANGUAGE_ISC, "iso9.isc")
        return doc, isc_to_compiled_map(doc)

    def test_map_declares_languages(self, compiled):
        doc, cm = compiled
        assert doc.languages == ("kur", "ckv")
        assert cm.languages == ("kur", "ckv")

    def test_no_selection_generic_rows(self, compiled):
        _, cm = compiled
        assert execute_stage(cm, "main", "қҫ") == "ķş"

    def test_kur_selection(self, compiled):
        _, cm = compiled
        assert execute_stage(cm, "main", "қҫ", language="kur") == "kş"

    def test_ckv_selection(self, compiled):
        _, cm = compiled
        assert execute_stage(cm, "main", "қҫ", language="ckv") == "ķs"

    def test_undeclared_selection_generic_rows(self, compiled):
        _, cm = compiled
        assert execute_stage(cm, "main", "қҫ", language="bel") == "ķş"

    def test_public_api_language_parameter(self, tmp_path, compiled):
        _, cm = compiled
        import interscript

        maps_dir = tmp_path / "maps"
        maps_dir.mkdir()
        payload = {
            "schemaVersion": 1,
            "systemCode": cm.system_code,
            "dependencies": [],
            "languages": list(cm.languages),
            "stages": [
                {
                    "name": "main",
                    "rules": [
                        {
                            "kind": "parallel",
                            "rules": [
                                {
                                    "kind": "sub",
                                    "from": {"kind": "string", "value": "қ"},
                                    "to": {"kind": "string", "value": "ķ"},
                                },
                                {
                                    "kind": "sub",
                                    "from": {"kind": "string", "value": "қ"},
                                    "to": {"kind": "string", "value": "k"},
                                    "when": ["kur"],
                                },
                            ],
                        }
                    ],
                }
            ],
            "aliases": {},
            "functions": {},
        }
        (maps_dir / f"{cm.system_code}.json").write_text(json.dumps(payload), encoding="utf-8")
        rt = interscript.Runtime([tmp_path])
        assert rt.transliterate(cm.system_code, "қ") == "ķ"
        assert rt.transliterate(cm.system_code, "қ", language="kur") == "k"


class TestOverridePlacement:
    """§4.2.6 (WO17, cross-grammar parity finding): ALL override rows —
    replacements AND additions — join the expansion's trailing parallel
    block, so the whole expansion shares one longest-match pass. The
    pre-parity behavior appended unmatched additions as bare stage
    rules, splitting the pass (found by maps scripts/parse-parity.mjs
    on bgnpcgn-tha / alalc-tha: 344 vs 327+17, 1523 vs 327+1196)."""

    SRC = """
system "test-ovr-place" {
  ruleset rs {
    parallel {
      sub "a" "x"
      sub "b" "y"
    }
  }
  stage main {
    use rs override {
      sub "a" "A"
      sub "c" "Z"
    }
  }
}
"""

    def test_additions_join_the_trailing_parallel(self):
        doc = parse_isc(self.SRC)
        body = doc.stages[0].items
        assert len(body) == 1, f"expected one pass, got {len(body)} items"
        blk = body[0]
        froms = [r.from_source for r in blk.rules if getattr(r, "from_source", None)]
        # kept row keeps its order; overrides join after it
        assert froms == ['"b"', '"a"', '"c"']

    def test_expansion_executes_as_one_pass(self):
        doc = parse_isc(self.SRC)
        cm = isc_to_compiled_map(doc)
        from interscript.executor import execute_stage

        # one longest-match pass over the joined block: "ac" -> "AZ"
        assert execute_stage(cm, "main", "ac") == "AZ"
        assert execute_stage(cm, "main", "ab") == "Ay"
