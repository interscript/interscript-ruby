# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""interscript-py — Python runtime for Interscript.

Executes the compiled JSON-IR map artifact (`interscript.maps.ir.v1`)
built by interscript/maps CI and consumed identically by the
TypeScript runtime. Deterministic transliteration over the interscript
map corpus (300+ authority-backed systems).

    import interscript

    interscript.add_load_path("/path/to/interscript-maps-ir")
    interscript.transliterate("un-bul-Cyrl-Latn-1977", "нос Бяга БЯГА")
    # -> "nos Byaga BYAGA"

The maps artifact is a release artifact, never bundled: point
`INTERSCRIPT_MAPS_IR` at an extracted artifact directory, call
`add_load_path()`, or run `python -m interscript.artifact_fetch` to
pull the latest release into the default cache.
"""

from __future__ import annotations

from pathlib import Path
from typing import TypeVar

from .errors import (
    ArtifactIntegrityError,
    AsyncFunctionError,
    IscParseError,
    MapFormatError,
    MapLogicError,
    MapNotFoundError,
)
from .isc import IscDocument, isc_to_compiled_map, parse_isc
from .loader import (
    MapLoader,
    default_load_paths,
    extract_release_tarball,
    load_manifest,
    verify_artifact,
)

T = TypeVar("T")

DEFAULT_STAGE = "main"


class Runtime:
    """A map runtime bound to a set of artifact load paths.

    Mirrors the TS `Intercript` class: default stage "main", dependency
    maps resolved through the same loader.
    """

    def __init__(
        self,
        load_paths: list[Path | str] | None = None,
        *,
        verify: bool = False,
        stage: str = DEFAULT_STAGE,
    ) -> None:
        self.loader = MapLoader(load_paths, verify=verify)
        self.default_stage = stage

    def add_load_path(self, path: Path | str) -> None:
        self.loader.add_load_path(path)

    def map_list(self) -> list[str]:
        return self.loader.map_list()

    def map_exist(self, system_code: str) -> bool:
        return self.loader.map_exist(system_code)

    def load_map(self, system_code: str):
        return self.loader.load(system_code)

    def transliterate(
        self,
        system_code: str,
        text: str,
        stage: str | None = None,
        language: str | None = None,
    ) -> str:
        """Apply a transliteration system to `text` (default stage: "main").

        `language` is the ISC-WF-1 W3 caller selection: when it names one
        of the map's declared `languages`, `when`-guarded rules for it
        apply (and beat unguarded same-from rules); any other value makes
        every guard inert (§5.1).
        """
        from .executor import execute_stage

        map_ = self.loader.load(system_code)
        return execute_stage(
            map_, stage or self.default_stage, text, self.loader, language
        )


def _default_runtime() -> Runtime:
    """Module-level runtime; resolves paths from `$INTERSCRIPT_MAPS_IR`
    and the default cache dir. Paths added later via `add_load_path`."""
    global _runtime
    if _runtime is None:
        _runtime = Runtime(default_load_paths())
    return _runtime


_runtime: Runtime | None = None


def add_load_path(path: Path | str) -> None:
    """Register an artifact directory (or release tarball)."""
    _default_runtime().add_load_path(path)


def map_list() -> list[str]:
    return _default_runtime().map_list()


def map_exist(system_code: str) -> bool:
    return _default_runtime().map_exist(system_code)


def load_map(system_code: str):
    """Parse and cache a compiled map (returns a CompiledMap)."""
    return _default_runtime().load_map(system_code)


def transliterate(
    system_code: str,
    text: str,
    stage: str | None = None,
    language: str | None = None,
) -> str:
    """Apply a transliteration system to `text` (default stage: "main").

    `language` selects one of the map's declared languages (ISC-WF-1 W3,
    `--language kur` in the CLI contract); guards are inert otherwise.
    """
    return _default_runtime().transliterate(system_code, text, stage, language)


__all__ = [
    "DEFAULT_STAGE",
    "ArtifactIntegrityError",
    "AsyncFunctionError",
    "IscDocument",
    "IscParseError",
    "MapFormatError",
    "MapLoader",
    "MapLogicError",
    "MapNotFoundError",
    "Runtime",
    "add_load_path",
    "default_load_paths",
    "extract_release_tarball",
    "isc_to_compiled_map",
    "load_manifest",
    "load_map",
    "map_exist",
    "map_list",
    "parse_isc",
    "transliterate",
    "verify_artifact",
]
