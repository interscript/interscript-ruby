# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Model-layer tests: tokens (pure), loader/registry contracts (pure),
and the frozen conformance fixtures (needs local IMF zips)."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from interscript.models.tokens import BYTE_OFFSET, EOS_ID, decode, encode


def _conformance_dir() -> Path:
    env = os.environ.get("INTERSCRIPT_CONFORMANCE_DIR", "")
    if env:
        return Path(env).expanduser()
    return Path.home() / "src" / "interscript" / "interscript-models" / "conformance"


CONFORMANCE_DIR = _conformance_dir()

# zip discovery: $INTERSCRIPT_MODEL_ZIPS dir, or the well-known local
# artifact locations on this machine (CI sets the env var explicitly).
_ZIP_HINTS = [
    os.environ.get("INTERSCRIPT_MODEL_ZIPS", ""),
    str(Path.home() / ".cache" / "interscript" / "models"),
    str(Path.home() / ".cache" / "secryst" / "models"),
    "/Users/mulgogi/src/interscript/.tmp-urd-arms",
]


def _find_zip(model_id: str) -> Path | None:
    for hint in _ZIP_HINTS:
        root = Path(hint) if hint else None
        if root is None or not root.is_dir():
            continue
        for z in sorted(root.glob(f"{model_id}*.zip")):
            return z
        # registry layout: <cache>/models/<id>/<filename>
        nested = root / model_id
        if nested.is_dir():
            for z in sorted(nested.glob("*.zip")):
                return z
    return None


class TestTokens:
    def test_encode_byte_plus_3_with_trailing_eos(self):
        assert encode("A") == [ord("A") + BYTE_OFFSET, EOS_ID]
        assert encode("é") == [0xC3 + BYTE_OFFSET, 0xA9 + BYTE_OFFSET, EOS_ID]

    def test_encode_empty_is_eos_only(self):
        assert encode("") == [EOS_ID]

    def test_decode_stops_at_eos(self):
        assert decode([65 + BYTE_OFFSET, EOS_ID, 66 + BYTE_OFFSET]) == "A"

    def test_decode_roundtrip(self):
        for text in ["καλημέρα", "คำ", "Здра́вствуйте"]:
            assert decode(encode(text)[:-1]) == text


class TestConformanceFixturesPresent:
    def test_six_families_exist(self):
        if not CONFORMANCE_DIR.is_dir():
            pytest.skip(f"conformance dir not found: {CONFORMANCE_DIR}")
        families = sorted(CONFORMANCE_DIR.glob("*-vectors.json"))
        assert len(families) == 6, f"expected six fixture families, got {families}"


@pytest.mark.ml
@pytest.mark.parametrize(
    "family",
    [
        "fas-diac-base",
        "khm-phonemic",
        "tha-g2p-lex",
        "tha-phonemic",
        "urd-diac-base",
        "urd-g2p-base",
    ],
)
def test_conformance_byte_identical(family):
    from interscript.conformance import load_vectors, run_vectors

    vectors_path = CONFORMANCE_DIR / f"{family}-vectors.json"
    if not vectors_path.is_file():
        pytest.skip(f"vectors not found: {vectors_path}")

    vf = load_vectors(vectors_path)
    zip_path = _find_zip(vf.model)
    if zip_path is None:
        pytest.skip(
            f"{vf.model}: no local zip (set INTERSCRIPT_MODEL_ZIPS or run "
            "`interscript.models` registry resolve)"
        )
    if family == "tha-phonemic":
        # Upstream artifact bug (interscript-models): the released
        # tha-phonemic-1.0.zip (sha256 534bc689..., identical to the
        # release's .sha256 sidecar) carries internal metadata
        # id=tha-g2p-lex-1.0. The weights are correct (vectors decode
        # 12/12), only metadata.yaml is mislabeled — tolerate the id,
        # keep outputs byte-exact.
        result = run_vectors(vectors_path, zip_path, strict_id=False)
    else:
        result = run_vectors(vectors_path, zip_path)
    assert result.ok, (
        f"{family}: {result.total - result.passed}/{result.total} vectors differ:\n"
        + "\n".join(
            f"  src={v['src']!r}\n  want={v['out']!r}\n  got ={actual!r}"
            for v, actual in result.failures[:5]
        )
    )
