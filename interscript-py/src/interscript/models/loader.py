# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""IMF v1 zip loading: sha256 verification + extraction.

Port of interscript-ml's `loader.py` (the sha256 verification the WO
pins); unchanged contract.
"""

from __future__ import annotations

import hashlib
import zipfile
from dataclasses import dataclass
from pathlib import Path

import yaml


class ModelFormatError(ValueError):
    """The zip is not a valid IMF v1 artifact (or fails integrity)."""


@dataclass(frozen=True)
class Manifest:
    id: str
    task: str
    decoder: str
    precision: str
    opset: int
    sha256: dict[str, str]


def load_manifest(zip_path: Path | str) -> Manifest:
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
        for required in ("metadata.yaml", "encoder.onnx", "decoder.onnx"):
            if required not in names:
                raise ModelFormatError(f"missing required file: {required}")
        raw = yaml.safe_load(zf.read("metadata.yaml"))
        if raw.get("format") != "imf-v1":
            raise ModelFormatError(f"unsupported format: {raw.get('format')!r}")
        if raw.get("tokenizer") != "bytes":
            raise ModelFormatError(
                f"tokenizer {raw.get('tokenizer')!r}: this runtime is byte-level only"
            )
        return Manifest(
            id=raw["id"],
            task=raw["task"],
            decoder=raw.get("decoder", "plain"),
            precision=raw.get("precision", "fp32"),
            opset=int(raw.get("opset", 14)),
            sha256=dict(raw.get("sha256", {})),
        )


def verify_and_read(zip_path: Path | str) -> dict[str, bytes]:
    """Read .onnx members after verifying each sha256 against the
    manifest."""
    manifest = load_manifest(zip_path)
    graphs: dict[str, bytes] = {}
    with zipfile.ZipFile(zip_path) as zf:
        for name in [n for n in zf.namelist() if n.endswith(".onnx")]:
            member = zf.read(name)
            recorded = manifest.sha256.get(name)
            if recorded is None:
                raise ModelFormatError(f"{name} is not covered by metadata sha256")
            actual = hashlib.sha256(member).hexdigest()
            if actual != recorded:
                raise ModelFormatError(
                    f"{name} sha256 mismatch: zip has {actual}, "
                    f"metadata says {recorded}"
                )
            graphs[name] = member
    return graphs
