# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Fetch the compiled JSON-IR map artifact from GitHub Releases.

The canonical data channel (house rule): GitHub Releases with a sha256
sidecar — never raw URLs.

    python -m interscript.artifact_fetch [--version 2.5.2] [--dest DIR]

Downloads `interscript-maps-ir-<version>.tar.gz` (+ `.sha256`) from
interscript/maps, verifies the tarball, and extracts it into
`~/.cache/interscript/maps-ir/` (override with `--dest` or
`$INTERSCRIPT_CACHE`), where the loader finds it by default.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

REPO = "interscript/maps"


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while chunk := fh.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def latest_version() -> str:
    import json

    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/releases/latest",
        headers={"Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(req) as response:
        payload = json.load(response)
    tag = payload["tag_name"]
    return tag.removeprefix("v")


def fetch(version: str, dest: Path) -> Path:
    base = f"https://github.com/{REPO}/releases/download/v{version}"
    name = f"interscript-maps-ir-{version}.tar.gz"
    dest.mkdir(parents=True, exist_ok=True)
    tarball = dest / name

    if not tarball.is_file():
        print(f"downloading {name} ...", file=sys.stderr)
        urllib.request.urlretrieve(f"{base}/{name}", tarball)
    sidecar = dest / f"{name}.sha256"
    if not sidecar.is_file():
        urllib.request.urlretrieve(f"{base}/{name}.sha256", sidecar)

    expected = sidecar.read_text(encoding="utf-8").split()[0]
    actual = _sha256_file(tarball)
    if actual != expected:
        raise SystemExit(f"{name}: sha256 mismatch (have {actual}, release says {expected})")

    # Extract into a sibling dir the loader resolves by default.
    root = dest / "maps-ir" / version
    if not (root / "manifest.json").is_file():
        from .loader import extract_release_tarball

        extract_release_tarball(tarball, root)
    print(f"artifact ready: {root}")
    return root


def main(argv: list[str] | None = None) -> int:
    import os

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=None, help="maps release tag (default: latest)")
    parser.add_argument(
        "--dest",
        default=os.environ.get("INTERSCRIPT_CACHE", Path.home() / ".cache" / "interscript"),
    )
    args = parser.parse_args(argv)
    version = args.version or latest_version()
    fetch(version, Path(args.dest).expanduser())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
