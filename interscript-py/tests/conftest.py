# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Shared fixtures.

- `artifact_dir` — the bundled curated subset of the compiled JSON-IR
  artifact (or a full artifact via `$INTERSCRIPT_MAPS_IR`).
- `maps_src` — the interscript/maps checkout that holds the .isc
  sources with embedded tests (skipped when absent).
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).parent
BUNDLED_ARTIFACT = TESTS_DIR / "data" / "maps-ir"


def _full_artifact_from_env() -> Path | None:
    env = os.environ.get("INTERSCRIPT_MAPS_IR", "")
    for part in env.split(":") if env else []:
        p = Path(part).expanduser()
        if p.is_dir():
            return p
    return None


@pytest.fixture(scope="session")
def artifact_dir() -> Path:
    full = _full_artifact_from_env()
    root = full if full is not None else BUNDLED_ARTIFACT
    if not root.is_dir():
        pytest.skip(f"no maps-ir artifact at {root}")
    return root


@pytest.fixture(scope="session")
def maps_src() -> Path:
    env = os.environ.get("INTERSCRIPT_MAPS_SRC", "")
    candidates = [Path(env)] if env else [Path.home() / "src" / "interscript" / "maps"]
    for c in candidates:
        if (c / "maps").is_dir():
            return c
    pytest.skip("interscript/maps checkout not found (set INTERSCRIPT_MAPS_SRC)")


@pytest.fixture()
def loader(artifact_dir):
    from interscript.loader import MapLoader

    return MapLoader([artifact_dir])


@pytest.fixture()
def runtime(artifact_dir):
    import interscript

    rt = interscript.Runtime([artifact_dir])
    yield rt
