# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Public API surface tests."""

from __future__ import annotations

import pytest

import interscript


def test_transliterate_known_vector(runtime):
    # From the map's own embedded tests block (un-bul-Cyrl-Latn-1977).
    assert runtime.transliterate("un-bul-Cyrl-Latn-1977", "нос Бяга БЯГА") == "nos Byaga BYAGA"


def test_transliterate_module_level(artifact_dir):
    interscript.add_load_path(artifact_dir)
    try:
        assert (
            interscript.transliterate("un-ukr-Cyrl-Latn-2012", "Україна") == "Ukraina"
        )
    finally:
        # Reset the module runtime so other tests start clean.
        interscript._runtime = None


def test_map_list_and_exist(runtime):
    names = runtime.map_list()
    assert "un-bul-Cyrl-Latn-1977" in names
    assert runtime.map_exist("un-bul-Cyrl-Latn-1977")
    assert not runtime.map_exist("does-not-exist")


def test_map_not_found_raises(runtime):
    with pytest.raises(interscript.MapNotFoundError):
        runtime.transliterate("does-not-exist", "x")


def test_load_map_returns_compiled_map(runtime):
    m = runtime.load_map("un-bul-Cyrl-Latn-1977")
    assert m.system_code.endswith("1977")
    assert any(s.name == "main" for s in m.stages)
