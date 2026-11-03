# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""interscript.models — the model layer (IMF v1 / ByT5 ONNX).

Fold-in of the house ONNX runtime (interscript-ml, now superseded by
the `secryst` package — that package remains the canonical model
runtime; this subpackage keeps the map+model-in-one-install surface
WO15 calls for). Kept deliberately small:

- `tokens`  — the canonical ByT5 byte table (byte b -> id b+3, trailing
  EOS). Raw text bytes are NOT the id sequence.
- `loader`  — IMF v1 zip manifest parsing + per-member sha256
  verification (the corrupt-download failure mode fails loudly).
- `registry`— models.yaml index resolve + cached download
  (`index-vN` GitHub Releases, sha256-verified, never raw URLs).
- `model`   — `Model.load(path-or-id)` + single-row-greedy decode (the
  contract the frozen conformance fixtures pin). Beam search stays in
  the secryst package.

Optional extra: `pip install interscript-py[ml]`.
"""

from __future__ import annotations

from .loader import Manifest, ModelFormatError, load_manifest, verify_and_read
from .tokens import BYTE_OFFSET, EOS_ID, PAD_ID, UNK_ID, decode, encode

__all__ = [
    "BYTE_OFFSET",
    "EOS_ID",
    "PAD_ID",
    "UNK_ID",
    "Manifest",
    "Model",
    "ModelFormatError",
    "decode",
    "encode",
    "load_manifest",
    "verify_and_read",
]


def __getattr__(name: str):  # lazy: keeps numpy/onnxruntime off the maps-only path
    if name == "Model":
        from .model import Model

        return Model
    if name == "RegistryError":
        from .registry import RegistryError

        return RegistryError
    if name == "resolve":
        from .registry import resolve

        return resolve
    raise AttributeError(name)
