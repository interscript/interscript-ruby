# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Reverse-mode parity — ported from interscript-rs ``tests/reverse.rs``,
whose expectations are ruby ground truth (``Document#reverse`` over
interscript-ruby origin/main, spec'd by spec/reversibility_spec.rb).

Fixtures: ``tests/data/reverse_maps/*.isc`` (vendored from
interscript-rs tests/reverse_maps/, plus rev-upcase-repeat for the
repeat-item deviation).

Documented ruby-crash deviations surface as named MapLogicErrors at
reverse time (mirroring rs ``Error::Unsupported`` messages):

- a repeat (maybe/some) item under a ``to upcase``/``to downcase`` sub
- a boundary hoist that consumes the whole from group
- a funcall outside the reverse_function map (upcase has no entry)
- an unhandled item kind in the transfer walk
"""

from __future__ import annotations

from pathlib import Path

import pytest

from interscript import Runtime
from interscript._ir_types import (
    AliasItem,
    CompiledMap,
    GroupItem,
    Stage,
    StringItem,
    SubRule,
)
from interscript.errors import MapLogicError, MapNotFoundError
from interscript.isc import isc_to_compiled_map, parse_isc
from interscript.reverse import reverse_map, reverse_name

FIXTURES_DIR = Path(__file__).parent / "data" / "reverse_maps"


def _load_sources() -> dict[str, str]:
    """Load every fixture under both its file stem and its system code
    (dependency targets are file stems; top-level loads use the code)."""
    sources: dict[str, str] = {}
    for path in sorted(FIXTURES_DIR.glob("*.isc")):
        src = path.read_text(encoding="utf-8")
        doc = parse_isc(src, filename=str(path))
        sources[path.stem] = src
        sources[doc.system_code] = src
    return sources


SOURCES = _load_sources()


class _DictLoader:
    """MapResolver over the in-memory fixture corpus (plus try_load /
    register for the runtime fallback contract)."""

    def __init__(self, compiled: dict[str, CompiledMap]) -> None:
        self._compiled = compiled

    def load(self, system_code: str) -> CompiledMap:
        try:
            return self._compiled[system_code]
        except KeyError:
            raise MapNotFoundError(system_code) from None

    def try_load(self, system_code: str) -> CompiledMap | None:
        return self._compiled.get(system_code)

    def register(self, system_code: str, map_: CompiledMap) -> None:
        self._compiled[system_code] = map_


@pytest.fixture(scope="module")
def runtime() -> Runtime:
    compiled = {
        code: isc_to_compiled_map(parse_isc(src, filename=code))
        for code, src in SOURCES.items()
    }
    return Runtime(loader=_DictLoader(compiled))  # type: ignore[arg-type]


def compile_map(code: str) -> CompiledMap:
    return isc_to_compiled_map(parse_isc(SOURCES[code], filename=code))


def reverse_run(runtime: Runtime, map_id: str, text: str) -> str:
    """The mirror of the rs test's ``reverse_run`` helper (rt.load +
    reverse_document + execute): the runtime path, so dependency
    documents reverse with the parent exactly like rs."""
    return runtime.reverse(map_id, text)


# ---------------------------------------------------------------------------
# reverse_name (Document.reverse_name)
# ---------------------------------------------------------------------------


def test_reverse_name_swaps_source_and_target() -> None:
    # Document.reverse_name: >= 4 dash-parts swaps [2]/[3].
    assert reverse_name("alalc-bul-Cyrl-Latn-1997") == "alalc-bul-Latn-Cyrl-1997"
    # the swap is an involution: swapping back reproduces the input.
    assert reverse_name("alalc-bul-Latn-Cyrl-1997") == "alalc-bul-Cyrl-Latn-1997"


def test_reverse_name_strips_or_appends_the_suffix() -> None:
    # shorter names strip -reverse, else append it.
    assert reverse_name("some-map-reverse") == "some-map"
    assert reverse_name("short-x") == "short-x-reverse"
    assert reverse_name("a-b-c") == "a-b-c-reverse"


# ---------------------------------------------------------------------------
# reverse_map — rs reverse.rs parity slice
# ---------------------------------------------------------------------------


def test_parallel_rules_swap_and_reverse_order(runtime: Runtime) -> None:
    # Ruby: "phth" -> "phthh", "x" -> "x", "fats" -> "phaths".
    # (reversed rules ks->x, t->th, f->ph; "fats" hits t then f)
    assert reverse_run(runtime, "rev:parallel", "phth") == "phthh"
    assert reverse_run(runtime, "rev:parallel", "x") == "x"
    assert reverse_run(runtime, "rev:parallel", "fats") == "phaths"


def test_sequential_children_reverse_order(runtime: Runtime) -> None:
    # forward: ab->X then X->Q; reversed: Q->X then X->ab.
    assert reverse_run(runtime, "rev:sequence", "Q") == "ab"
    assert reverse_run(runtime, "rev:sequence", "X") == "ab"
    assert reverse_run(runtime, "rev:sequence", "ab") == "ab"
    assert reverse_run(runtime, "rev:sequence", "abq") == "abq"


def test_case_swap_downcases_the_from_tree(runtime: Runtime) -> None:
    # forward: sub "abc" to upcase; downcase.
    # reversed: title_case, then sub "abc" to downcase.
    # Ruby: "abc" -> "Abc", "abc ABC" -> "Abc ABC".
    assert reverse_run(runtime, "rev:case", "abc") == "Abc"
    assert reverse_run(runtime, "rev:case", "abc ABC") == "Abc ABC"


def test_boundary_constraints_pass_through_unchanged(runtime: Runtime) -> None:
    # forward: sub "x" "y" after boundary; sub "q" "r" before line_end.
    # Ruby reverse keeps the constraints on the same side: "r y" -> "r x"
    # (y->x fires after the boundary before end-of-string).
    assert reverse_run(runtime, "rev:boundary", "r y") == "r x"
    assert reverse_run(runtime, "rev:boundary", "yq") == "yq"
    assert reverse_run(runtime, "rev:boundary", "qr") == "qr"


def test_capture_and_ref_exchange_sides(runtime: Runtime) -> None:
    # forward: from "a" + capture("b" + maybe("c")) + "d" to "X" + ref(1)
    # reversed: from "X" + capture("b" + maybe("c")) to "a" + ref(1).
    assert reverse_run(runtime, "rev:capture", "Xbc") == "abcd"
    assert reverse_run(runtime, "rev:capture", "Xd") == "Xd"
    assert reverse_run(runtime, "rev:capture", "abcd") == "abcd"


def test_funcalls_invert_through_the_reverse_function_map(runtime: Runtime) -> None:
    # forward: separate separator "-"; compose.
    # reversed: decompose, then unseparate separator "-".
    assert reverse_run(runtime, "rev:funcall", "a-b-c") == "abc"
    assert reverse_run(runtime, "rev:funcall", "abc") == "abc"


def test_dependency_documents_reverse_with_the_parent(runtime: Runtime) -> None:
    # dep main: n->p, e->f. forward parent: m->n then run dep.
    # reversed parent: run reversed-dep (p->n, f->e) then n->m.
    # Ruby: "men" -> "mem", "pem" -> "mem".
    assert reverse_run(runtime, "rev:dep-main", "men") == "mem"
    assert reverse_run(runtime, "rev:dep-main", "pem") == "mem"


def test_real_corpus_map_reverses_like_ruby(runtime: Runtime) -> None:
    # Vendored alalc-bul-Cyrl-Latn-1997.isc; Ruby ground truth:
    assert reverse_run(runtime, "ALA-LC:bul-Cyrl:Latn:1997", "Kirillicata") == "Кириллиcата"
    assert reverse_run(runtime, "ALA-LC:bul-Cyrl:Latn:1997", "zapad") == "запад"
    assert reverse_run(runtime, "ALA-LC:bul-Cyrl:Latn:1997", "Sofiya") == "Софиyа"


def test_empty_reversed_from_disables_the_rule(runtime: Runtime) -> None:
    # sub "h" none (deletion): the reversed from is empty -> Ruby
    # marks it reverse_run: true so the executor skips it; the
    # compiled-IR form drops the rule. A forward-deletion map must not
    # infinite-expand on reverse.
    # Ruby ground truth: "hh" -> "hh", "hi" -> "hi".
    assert reverse_run(runtime, "rev:delete", "hh") == "hh"
    assert reverse_run(runtime, "rev:delete", "hi") == "hi"


def test_document_name_and_metadata_reverse(runtime: Runtime) -> None:
    doc = reverse_map(compile_map("ALA-LC:bul-Cyrl:Latn:1997"))
    # The system code has 3 dash-parts (colons separate the fields),
    # so Document.reverse_name appends the -reverse suffix.
    assert doc.system_code == "ALA-LC:bul-Cyrl:Latn:1997-reverse"
    assert doc.metadata is not None
    assert doc.metadata["source_script"] == "Latn"
    assert doc.metadata["destination_script"] == "Cyrl"
    # aliases and languages pass through untouched (rs: rdoc.aliases = self.aliases)
    forward = compile_map("ALA-LC:bul-Cyrl:Latn:1997")
    assert doc.aliases == forward.aliases
    assert doc.languages == forward.languages
    assert doc.dependencies == forward.dependencies


# ---------------------------------------------------------------------------
# Runtime reverse-name load fallback (ruby DSL.parse behavior)
# ---------------------------------------------------------------------------


def test_transliterate_resolves_a_missing_map_through_its_reverse_name(
    runtime: Runtime,
) -> None:
    # no "rev:parallel-reverse" map exists — the fallback loads
    # rev:parallel and returns its reverse (ruby DSL.parse behavior).
    assert runtime.transliterate("rev:parallel-reverse", "fats") == "phaths"
    # the fallback result is cached under the requested name.
    assert runtime.loader.try_load("rev:parallel-reverse") is not None


def test_missing_map_without_a_reverse_sibling_raises(runtime: Runtime) -> None:
    with pytest.raises(MapNotFoundError):
        runtime.transliterate("no-such-map-xyz", "x")


# ---------------------------------------------------------------------------
# Documented ruby-crash deviations surface as named errors
# ---------------------------------------------------------------------------


def test_upcase_funcall_reverse_is_unsupported_like_ruby() -> None:
    # The Ruby reverse_function map has no :upcase entry — reversing a
    # funcall upcase crashes there (nil.to_sym TypeError when the
    # reversed funcall executes). We raise cleanly at reverse time.
    with pytest.raises(MapLogicError, match=r"upcase has no reverse"):
        reverse_map(compile_map("rev:upcase"))


def test_repeat_item_under_to_upcase_raises_like_ruby() -> None:
    # Ruby Item::Repeat has no downcase/upcase: NoMethodError.
    with pytest.raises(MapLogicError, match=r"repeat item in a to-upcase/downcase sub"):
        reverse_map(compile_map("rev:upcase-repeat"))


def test_boundary_hoist_consuming_the_whole_from_group_raises_like_ruby() -> None:
    # Hand-built: a one-child group whose only child is boundary-like —
    # unreachable through the ISC converter (single-part concats
    # unwrap) but the same path rs guards with Error::Unsupported.
    boundary = AliasItem(name="boundary")
    rule = SubRule(
        from_=GroupItem(items=(boundary,)),
        to=StringItem(value="x"),
    )
    doc = CompiledMap(
        schema_version=1,
        system_code="unit:hoist",
        dependencies=(),
        stages=(Stage(name="main", rules=(rule,)),),
        aliases={},
        functions={},
    )
    with pytest.raises(
        MapLogicError, match=r"boundary hoist consumed the whole from group"
    ):
        reverse_map(doc)


def test_unhandled_item_kind_raises_like_ruby() -> None:
    # Ruby reverse_transfer_visit: raise "Type ... unhandled!"
    from interscript._ir_types import StageItem

    rule = SubRule(from_=StageItem(name="other"), to=StringItem(value="x"))
    doc = CompiledMap(
        schema_version=1,
        system_code="unit:unhandled",
        dependencies=(),
        stages=(Stage(name="main", rules=(rule,)),),
        aliases={},
        functions={},
    )
    with pytest.raises(MapLogicError, match=r"unhandled in reverse_transfer_visit"):
        reverse_map(doc)
