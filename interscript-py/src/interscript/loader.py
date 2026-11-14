# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Loader for the compiled JSON-IR map artifact (`interscript.maps.ir.v1`).

Artifact layout (built by `interscript/maps` CI,
`scripts/build-json-ir-artifact.mjs`):

    manifest.json          {schema, source, generatedAt, count, systems}
    SHA256SUMS             "<sha256>  <path>" per artifact file
    maps/<system>.json     one compiled map per system (libs included)

The canonical distribution channel is GitHub Releases
(interscript/maps, asset `interscript-maps-ir-<version>.tar.gz` with a
`.sha256` sidecar) — raw URLs are never used for data paths.
"""

from __future__ import annotations

import hashlib
import json
import os
import tarfile
from pathlib import Path

from ._ir_types import CompiledMap, map_from_json
from .context import MapResolver
from .errors import ArtifactIntegrityError, MapFormatError, MapNotFoundError

MANIFEST_NAME = "manifest.json"
SUMS_NAME = "SHA256SUMS"
ENV_LOAD_PATH = "INTERSCRIPT_MAPS_IR"


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while chunk := fh.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify_artifact(root: Path) -> None:
    """Verify every artifact file against SHA256SUMS. The corrupt-download
    failure mode fails loudly here."""
    sums = root / SUMS_NAME
    if not sums.is_file():
        raise ArtifactIntegrityError(f"missing {SUMS_NAME} in {root}")
    for line in sums.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        expected, _, rel = line.partition("  ")
        member = root / rel
        if not member.is_file():
            raise ArtifactIntegrityError(f"{rel}: listed in {SUMS_NAME} but missing")
        actual = _sha256_file(member)
        if actual != expected:
            raise ArtifactIntegrityError(
                f"{rel}: sha256 mismatch (have {actual}, manifest says {expected})"
            )


def extract_release_tarball(tarball: Path, dest: Path) -> Path:
    """Extract a `interscript-maps-ir-<version>.tar.gz` release asset into
    `dest` (the tarball has no top-level directory). Returns the root."""
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tarball, "r:gz") as tf:
        tf.extractall(dest)
    return dest


class MapLoader(MapResolver):
    """Resolves system codes to compiled maps from one or more artifact
    directories (first hit wins), with an in-memory cache.

    Adding a new source = passing another strategy/resolver into
    `Runtime`, not editing this class (OCP).
    """

    def __init__(
        self,
        load_paths: list[Path | str] | None = None,
        *,
        verify: bool = False,
    ) -> None:
        self._paths: list[Path] = []
        self._verify_flag = verify
        self._verified: set[Path] = set()
        self._cache: dict[str, CompiledMap] = {}
        self._known: dict[str, Path] = {}
        for p in load_paths or []:
            self.add_load_path(p)

    def add_load_path(self, path: Path | str) -> None:
        root = Path(path).expanduser()
        if root.is_file() and root.suffix in (".gz", ".tgz"):
            # Release tarball: extract into a consumer-side cache dir.
            cache = _default_cache_dir() / ("extracted-" + root.name.replace(".tar.gz", ""))
            root = extract_release_tarball(root, cache)
        if not root.is_dir():
            raise MapFormatError(f"artifact directory not found: {root}")
        self._paths.insert(0, root)
        self._rescan(root)

    @property
    def load_paths(self) -> list[Path]:
        return list(self._paths)

    def _rescan(self, root: Path) -> None:
        maps_dir = root / "maps"
        if maps_dir.is_dir():
            for f in sorted(maps_dir.glob("*.json")):
                self._known.setdefault(f.stem, f)
        else:
            # Tolerate a bare directory of <system>.json files.
            for f in sorted(root.glob("*.json")):
                if f.name in (MANIFEST_NAME, SUMS_NAME):
                    continue
                self._known.setdefault(f.stem, f)

    def _read(self, path: Path) -> CompiledMap:
        if self._verify_flag and path.parent not in self._verified:
            verify_artifact(path.parent)
            self._verified.add(path.parent)
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise MapFormatError(f"{path}: invalid JSON ({exc})") from exc
        try:
            return map_from_json(raw)
        except (KeyError, TypeError, ValueError) as exc:
            raise MapFormatError(f"{path}: not a valid compiled map ({exc})") from exc

    def load(self, system_code: str) -> CompiledMap:
        cached = self._cache.get(system_code)
        if cached is not None:
            return cached
        path = self._known.get(system_code)
        if path is None:
            raise MapNotFoundError(
                system_code, load_paths=[str(p) for p in self._paths]
            )
        compiled = self._read(path)
        self._cache[system_code] = compiled
        return compiled

    def try_load(self, system_code: str) -> CompiledMap | None:
        try:
            return self.load(system_code)
        except MapNotFoundError:
            return None

    def map_list(self) -> list[str]:
        return sorted(self._known)

    def map_exist(self, system_code: str) -> bool:
        return system_code in self._known or system_code in self._cache

    def register(self, system_code: str, map_: CompiledMap) -> None:
        """Register a compiled map directly (bypasses load paths) — the
        mirror of interscript-ts's `MapLoader.register`. Used by the
        runtime's reverse-name load fallback to cache a reversed
        document under the requested name."""
        self._cache[system_code] = map_


def _default_cache_dir() -> Path:
    if env := os.environ.get("INTERSCRIPT_CACHE"):
        return Path(env)
    return Path.home() / ".cache" / "interscript"


def default_load_paths() -> list[Path]:
    """Artifact locations implied by the environment: `$INTERSCRIPT_MAPS_IR`
    (colon-separated), then the default cache dir, if they exist."""
    out: list[Path] = []
    env = os.environ.get(ENV_LOAD_PATH, "")
    for part in env.split(":") if env else []:
        p = Path(part).expanduser()
        if p.is_dir() or p.is_file():
            out.append(p)
    cache = _default_cache_dir() / "maps-ir"
    if cache.is_dir():
        out.append(cache)
    return out


def load_manifest(root: Path) -> dict:
    manifest = root / MANIFEST_NAME
    if not manifest.is_file():
        raise MapFormatError(f"missing {MANIFEST_NAME} in {root}")
    return json.loads(manifest.read_text(encoding="utf-8"))
