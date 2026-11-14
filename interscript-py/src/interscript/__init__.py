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
from .reverse import reverse_map, reverse_name

T = TypeVar("T")

DEFAULT_STAGE = "main"


class _ReversedDependencyResolver:
    """Serves reversed dependency documents under their FORWARD names
    (run rules reference the forward names) — the runtime-side half of
    rs's `reverse_document` dependency recursion."""

    def __init__(self, maps: dict[str, object]) -> None:
        self._maps = maps

    def load(self, system_code: str):
        try:
            return self._maps[system_code]
        except KeyError:
            raise MapNotFoundError(system_code) from None


class Runtime:
    """A map runtime bound to a set of artifact load paths.

    Mirrors the TS `Interscript` class: default stage "main", dependency
    maps resolved through the same loader.
    """

    def __init__(
        self,
        load_paths: list[Path | str] | None = None,
        *,
        verify: bool = False,
        stage: str = DEFAULT_STAGE,
        loader: MapLoader | None = None,
    ) -> None:
        # `loader` injects a custom resolver (tests, in-memory corpora);
        # default: the artifact loader over `load_paths`.
        self.loader: MapLoader = loader if loader is not None else MapLoader(
            load_paths, verify=verify
        )
        self.default_stage = stage

    def add_load_path(self, path: Path | str) -> None:
        self.loader.add_load_path(path)

    def map_list(self) -> list[str]:
        return self.loader.map_list()

    def map_exist(self, system_code: str) -> bool:
        return self.loader.map_exist(system_code)

    def load_map(self, system_code: str):
        """Parse and cache a compiled map (returns a CompiledMap).

        Carries the ruby `Interscript::DSL.parse` reverse-name fallback:
        a missing map whose reverse-named sibling exists loads that
        sibling and returns its reverse (cached under the requested
        name)."""
        try:
            return self.loader.load(system_code)
        except MapNotFoundError as original:
            fallback = reverse_name(system_code)
            if fallback == system_code:
                raise
            try:
                forward = self.loader.load(fallback)
            except MapNotFoundError:
                raise original from None
            reversed_doc = reverse_map(forward)
            self.loader.register(system_code, reversed_doc)
            return reversed_doc

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

        map_ = self.load_map(system_code)
        return execute_stage(
            map_, stage or self.default_stage, text, self.loader, language
        )

    def reverse(
        self,
        system_code: str,
        text: str,
        stage: str | None = None,
        language: str | None = None,
    ) -> str:
        """Reverse-mode transliteration — the `iscrs reverse` analog:
        load the map, reverse it (mirroring rs `reverse_document`, which
        recursively reverses embedded dependency documents — here the
        whole dependency closure is reversed and served to execution),
        then run one stage of the reversed document."""
        from .executor import execute_stage

        map_ = self.load_map(system_code)

        # rs: dependency documents reverse with the parent. Memoized
        # closure walk — cycles recurse in rs/ruby too, only repeat
        # work is skipped here.
        reversed_deps: dict[str, object] = {}

        def collect(m) -> None:
            for dep in m.dependencies:
                if dep in reversed_deps:
                    continue
                dep_map = self.loader.load(dep)
                reversed_deps[dep] = reverse_map(dep_map)
                collect(dep_map)

        collect(map_)

        reversed_doc = reverse_map(map_)
        loader = _ReversedDependencyResolver(reversed_deps) if reversed_deps else None
        return execute_stage(
            reversed_doc, stage or self.default_stage, text, loader, language
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


def reverse(
    system_code: str,
    text: str,
    stage: str | None = None,
    language: str | None = None,
) -> str:
    """Reverse-mode transliteration (`iscrs reverse` analog): load
    `system_code`, reverse the document (dependencies reverse with the
    parent), and transliterate `text` through it."""
    return _default_runtime().reverse(system_code, text, stage, language)


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
    "reverse",
    "reverse_map",
    "reverse_name",
    "transliterate",
    "verify_artifact",
]
