# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Model.load(zip) + single-row-greedy decode.

Port of interscript-ml's `model.py`, reduced to the path the frozen
conformance fixtures pin (WO51):

- encode: UTF-8 bytes, ids `byte + 3`, trailing EOS appended
- encoder: ONE row per call, no padding, no attention mask (the
  exported encoder takes `input_ids` only)
- decoder: greedy argmax until EOS, 512-step cap
- output: tokens `t -> byte(t - 3)`, decoded UTF-8

Batched decode without an attention mask corrupts encoder states and is
NOT part of the contract. Beam search lives in the `secryst` package.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from .loader import load_manifest, verify_and_read
from .tokens import EOS_ID, PAD_ID, decode, encode

MAX_STEPS = 512  # the conformance contract's decode cap


class Model:
    """A loaded, checksum-verified IMF v1 model."""

    def __init__(self, zip_path: Path | str):
        self.zip_path = Path(zip_path)
        self.manifest = load_manifest(self.zip_path)
        import onnxruntime as ort

        options = ort.SessionOptions()
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        graphs = verify_and_read(self.zip_path)
        self._encoder = ort.InferenceSession(
            graphs["encoder.onnx"], options, providers=_providers()
        )
        decoder_name = (
            "decoder-kv.onnx"
            if self.manifest.decoder == "kv" and "decoder-kv.onnx" in graphs
            else "decoder.onnx"
        )
        self._kv_session = decoder_name == "decoder-kv.onnx"
        self._decoder = ort.InferenceSession(
            graphs[decoder_name], options, providers=_providers()
        )
        self._pasts = {
            meta.name: _zero_past(meta)
            for meta in self._decoder.get_inputs()
            if meta.name.startswith("past_")
        }
        self._output_names = [o.name for o in self._decoder.get_outputs()]

    @classmethod
    def load(cls, path_or_id: Path | str, index_url: str | None = None) -> Model:
        """Accepts a zip path OR a model id from the models index
        (dynamic fetch: download -> verify -> cache)."""
        candidate = str(path_or_id)
        if candidate.endswith(".zip") or Path(candidate).exists():
            return cls(candidate)
        from .registry import resolve

        return cls(resolve(candidate, index_url))

    @property
    def id(self) -> str:
        return self.manifest.id

    def translate(self, text: str, max_len: int = MAX_STEPS) -> str:
        token_ids = self.generate(text, max_len=max_len)
        return decode(token_ids)

    def generate(self, text: str, max_len: int = MAX_STEPS) -> list[int]:
        ids = np.array([encode(text)], dtype=np.int64)
        if ids.shape[1] == 1:  # only the trailing EOS: empty input
            return []
        hidden = self._encoder.run(None, {"input_ids": ids})[0]
        if self._kv_session:
            return self._greedy_kv(hidden, max_len)
        return self._greedy_plain(hidden, max_len)

    def _greedy_kv(self, hidden, max_len: int) -> list[int]:
        pasts = dict(self._pasts)
        current = np.array([[PAD_ID]], dtype=np.int64)
        generated: list[int] = []
        for _ in range(max_len):
            outputs = self._decoder.run(
                None,
                {"input_ids": current, "encoder_hidden_states": hidden, **pasts},
            )
            results = dict(zip(self._output_names, outputs, strict=True))
            token = int(np.argmax(results["logits"][0, -1]))
            if token == EOS_ID:
                break
            generated.append(token)
            pasts = {
                name: results[name.replace("past_", "present_", 1)]
                for name in pasts
            }
            current = np.array([[token]], dtype=np.int64)
        return generated

    def _greedy_plain(self, hidden, max_len: int) -> list[int]:
        decoder_ids = np.array([[PAD_ID]], dtype=np.int64)
        generated: list[int] = []
        for _ in range(max_len):
            logits = self._decoder.run(
                None,
                {"input_ids": decoder_ids, "encoder_hidden_states": hidden},
            )[0]
            token = int(np.argmax(logits[0, -1]))
            if token == EOS_ID:
                break
            generated.append(token)
            decoder_ids = np.concatenate(
                [decoder_ids, np.array([[token]], dtype=np.int64)], axis=1
            )
        return generated

    def mount(self, funcall_name: str = "secryst") -> None:
        """Register this model as the handler for a map ML funcall, so
        compiled maps that call e.g. `secryst` run through it."""
        from .. import executor

        executor.register_async_function(
            funcall_name, lambda text, _opts=None, _m=self: _m.translate(text)
        )


def _providers() -> list[str]:
    import onnxruntime as ort

    available = ort.get_available_providers()
    preferred = [p for p in ("CPUExecutionProvider",) if p in available]
    return preferred or available


def _zero_past(meta):
    shape = meta.shape  # [batch, heads, past_seq, d_kv], dynamic dims are str
    heads = shape[1] if isinstance(shape[1], int) else 4
    d_kv = shape[3] if isinstance(shape[3], int) else 8
    dtype = np.float16 if meta.type == "tensor(float16)" else np.float32
    return np.zeros((1, heads, 0, d_kv), dtype=dtype)
