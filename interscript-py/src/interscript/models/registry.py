# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Model index resolution + cached downloads (the dynamic-fetch layer).

Port of interscript-ml's `registry.py`: resolve an id, reuse a verified
cache copy, or download + sha256-verify + atomically install into the
cache. The index is a GitHub Releases artifact (`index-vN`), never a
raw URL.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

import yaml

DEFAULT_INDEX_URL = (
    "https://github.com/interscript/interscript-models/releases/download/index-v12/models-index.yaml"
)
ENV_INDEX = "INTERSCRIPT_INDEX"
ENV_CACHE = "INTERSCRIPT_CACHE"


class RegistryError(ValueError):
    """The index cannot be fetched/parsed, or the id is unknown."""


@dataclass(frozen=True)
class Part:
    url: str
    sha256: str
    size: int


@dataclass(frozen=True)
class IndexEntry:
    id: str
    filename: str
    url: str
    sha256: str
    size: int
    precision: str
    task: str
    parts: tuple[Part, ...] = ()


def cache_dir() -> Path:
    if env := os.environ.get(ENV_CACHE):
        return Path(env)
    return Path.home() / ".cache" / "interscript"


def load_index(index_url: str | None = None) -> dict[str, IndexEntry]:
    source = index_url or os.environ.get(ENV_INDEX) or DEFAULT_INDEX_URL
    if source.startswith(("http://", "https://")):
        with urllib.request.urlopen(source) as response:
            text = response.read().decode("utf-8")
    else:
        text = Path(source).read_text(encoding="utf-8")
    raw = yaml.safe_load(text)
    if not isinstance(raw, dict) or raw.get("version") != 1:
        raise RegistryError("index must be a mapping with version: 1")
    entries: dict[str, IndexEntry] = {}
    for model_id, spec in raw.get("models", {}).items():
        parts = tuple(
            Part(url=part["url"], sha256=part["sha256"], size=int(part.get("size", 0)))
            for part in spec.get("parts", [])
        )
        entries[model_id] = IndexEntry(
            id=model_id,
            filename=spec["filename"],
            url=spec.get("url", ""),
            sha256=spec["sha256"],
            size=int(spec.get("size", 0)),
            precision=spec.get("precision", "fp32"),
            task=spec.get("task", ""),
            parts=parts,
        )
    return entries


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while chunk := fh.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _open_channel(url: str):
    if url.startswith("file://"):
        return open(urlparse(url).path, "rb")
    return urllib.request.urlopen(url)


def _download_parts(entry: IndexEntry, downloaded: Path) -> None:
    """Stream parts into `downloaded` in index order, verifying each
    part's sha256 as it lands (models over GitHub's 2 GiB asset cap)."""
    with downloaded.open("ab") as out:
        for index, part in enumerate(entry.parts):
            digest = hashlib.sha256()
            with _open_channel(part.url) as remote:
                while chunk := remote.read(1024 * 1024):
                    out.write(chunk)
                    digest.update(chunk)
            actual = digest.hexdigest()
            if actual != part.sha256:
                raise RegistryError(
                    f"part {index} of {entry.filename} sha256 mismatch: "
                    f"got {actual}, index says {part.sha256}"
                )


def resolve(model_id: str, index_url: str | None = None) -> Path:
    """Return a verified local zip path for `model_id`, downloading and
    installing into the cache when needed. Cache hits are re-verified
    against the index sha256 — never returns an unverified file."""
    entries = load_index(index_url)
    if model_id not in entries:
        raise RegistryError(f"unknown model id {model_id!r} (known: {sorted(entries)})")
    entry = entries[model_id]
    target = cache_dir() / "models" / model_id / entry.filename
    if target.is_file() and _sha256_file(target) == entry.sha256:
        return target

    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=target.parent, suffix=".part")
    os.close(fd)
    downloaded = Path(tmp_name)
    try:
        if entry.parts:
            _download_parts(entry, downloaded)
        elif entry.url.startswith("file://"):
            source = Path(urlparse(entry.url).path)
            if not source.is_file():
                raise RegistryError(f"channel file missing: {source}")
            shutil.copyfile(source, downloaded)  # file:// is a mirror, not a move
        else:
            urllib.request.urlretrieve(entry.url, downloaded)
        actual = _sha256_file(downloaded)
        if actual != entry.sha256:
            raise RegistryError(
                f"downloaded {entry.filename} sha256 mismatch: got {actual}, "
                f"index says {entry.sha256}"
            )
        os.replace(downloaded, target)
    finally:
        if downloaded.exists():
            downloaded.unlink()
    return target
