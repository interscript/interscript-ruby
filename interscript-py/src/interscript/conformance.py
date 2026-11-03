# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Conformance harness — replay frozen vectors byte-exactly.

Fixture families live in interscript-models' `conformance/` (six
families: fas-diac-base, khm-phonemic, tha-g2p-lex, tha-phonemic,
urd-diac-base, urd-g2p-base). A vector file pins `model`,
`index_version`, `decode.mode` and a list of {src, out} rows; outputs
compare byte-exact (no normalization, no CER tolerance).

    from interscript.conformance import run_vectors
    failures = run_vectors("urd-diac-base-vectors.json", zip_path)
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

SUPPORTED_DECODE_MODES = {"single-row-greedy"}


@dataclass(frozen=True)
class VectorFile:
    model: str
    index_version: int
    decode_mode: str
    vectors: tuple[dict, ...]
    source: str | None
    rows: int | None


def load_vectors(path: Path | str) -> VectorFile:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    model = raw["model"]
    index_version = int(raw["index_version"])
    decode_mode = raw.get("decode", {}).get("mode", "single-row-greedy")
    if decode_mode not in SUPPORTED_DECODE_MODES:
        raise ValueError(f"unsupported decode mode: {decode_mode!r}")
    vectors = tuple(raw["vectors"])
    for v in vectors:
        if "src" not in v or "out" not in v:
            raise ValueError(f"{path}: vector row missing src/out: {v!r}")
    return VectorFile(
        model=model,
        index_version=index_version,
        decode_mode=decode_mode,
        vectors=vectors,
        source=raw.get("source"),
        rows=raw.get("rows"),
    )


@dataclass(frozen=True)
class ConformanceResult:
    model: str
    total: int
    passed: int
    failures: tuple[tuple[dict, str], ...]  # (vector, actual)

    @property
    def ok(self) -> bool:
        return self.passed == self.total


def run_vectors(
    vectors_path: Path | str,
    zip_path: Path | str,
    *,
    strict_id: bool = True,
) -> ConformanceResult:
    """Decode every vector's src through the model and compare byte-exact.

    `strict_id=False` tolerates a zip whose internal metadata id differs
    from the pinned model id (outputs are still checked byte-exact) —
    used for the tha-phonemic-1.0 release, whose metadata.yaml id is
    mislabeled upstream while the weights are correct.
    """
    vf = load_vectors(vectors_path)
    from .models.model import Model

    model = Model.load(zip_path)
    if model.manifest.id != vf.model and strict_id:
        raise ValueError(f"zip is {model.manifest.id!r}, vectors pin {vf.model!r}")
    failures: list[tuple[dict, str]] = []
    for v in vf.vectors:
        actual = model.translate(v["src"])
        if actual != v["out"]:
            failures.append((v, actual))
    return ConformanceResult(
        model=vf.model,
        total=len(vf.vectors),
        passed=len(vf.vectors) - len(failures),
        failures=tuple(failures),
    )
