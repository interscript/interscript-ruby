# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Loader tests: artifact verification, map resolution, dependency
lookup, tarball handling."""

from __future__ import annotations

import json

import pytest

from interscript.errors import (
    ArtifactIntegrityError,
    MapFormatError,
    MapNotFoundError,
)
from interscript.loader import MapLoader, load_manifest, verify_artifact


def test_manifest_shape(artifact_dir):
    manifest = load_manifest(artifact_dir)
    assert manifest["schema"] == "interscript.maps.ir.v1"
    assert manifest["count"] == len(manifest["systems"])
    assert (artifact_dir / "maps" / f"{manifest['systems'][0]}.json").is_file()


def test_sha256_verification_passes(artifact_dir):
    verify_artifact(artifact_dir)


def test_sha256_verification_catches_tamper(artifact_dir, tmp_path):
    import shutil

    tampered = tmp_path / "artifact"
    shutil.copytree(artifact_dir, tampered)
    victim = next((tampered / "maps").glob("*.json"))
    doc = json.loads(victim.read_text(encoding="utf-8"))
    doc["systemCode"] = "tampered"
    victim.write_text(json.dumps(doc) + "\n", encoding="utf-8")
    with pytest.raises(ArtifactIntegrityError, match="sha256 mismatch"):
        verify_artifact(tampered)


def test_load_and_cache(loader):
    m1 = loader.load("un-bul-Cyrl-Latn-1977")
    m2 = loader.load("un-bul-Cyrl-Latn-1977")
    assert m1 is m2
    # Files are keyed by stem; the doc's systemCode is the display name
    # (e.g. "UN:bul-Cyrl:Latn:1977") kept verbatim from the .isc source.
    assert m1.system_code.endswith("1977")
    assert m1.schema_version == 1


def test_map_not_found(loader):
    with pytest.raises(MapNotFoundError, match="no-such-map"):
        loader.load("no-such-map")


def test_map_list_and_exist(loader):
    names = loader.map_list()
    assert "posix" in names
    assert loader.map_exist("posix")
    assert not loader.map_exist("no-such-map")


def test_dependencies_recorded(loader):
    m = loader.load("un-bul-Cyrl-Latn-1977")
    assert isinstance(m.dependencies, tuple)
    for dep in m.dependencies:
        assert loader.map_exist(dep), f"dependency {dep} missing from artifact"


def test_tarball_extract(tmp_path):
    # Build a minimal tarball in the artifact layout, then extract.
    import tarfile

    root = tmp_path / "src"
    (root / "maps").mkdir(parents=True)
    (root / "manifest.json").write_text(
        json.dumps({"schema": "interscript.maps.ir.v1", "count": 0, "systems": []}) + "\n"
    )
    tarball = tmp_path / "interscript-maps-ir-test.tar.gz"
    with tarfile.open(tarball, "w:gz") as tf:
        for f in sorted(root.rglob("*")):
            tf.add(f, arcname=f.relative_to(root))

    from interscript.loader import extract_release_tarball

    dest = tmp_path / "out"
    extracted = extract_release_tarball(tarball, dest)
    assert (extracted / "manifest.json").is_file()
    assert extracted == dest


def test_missing_artifact_dir(tmp_path):
    with pytest.raises(MapFormatError):
        MapLoader([tmp_path / "nope"])


def test_invalid_map_json(tmp_path):
    (tmp_path / "maps").mkdir()
    (tmp_path / "maps" / "bad.json").write_text("{ not json")
    loader = MapLoader([tmp_path])
    with pytest.raises(MapFormatError, match="invalid JSON"):
        loader.load("bad")
