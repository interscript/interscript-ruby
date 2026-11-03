# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""The canonical ByT5 byte table (fixed, no vocab files).

Stock google/byt5 tokenizers map UTF-8 byte b to id b+3 and append
EOS(1); pad=0, unk=2. Ids are NOT raw byte values — feeding
text.encode() directly produces silent garbage on real models.
"""

from __future__ import annotations

BYTE_OFFSET = 3
PAD_ID = 0
EOS_ID = 1
UNK_ID = 2


def encode(text: str) -> list[int]:
    """Canonical byte-level tokenization (byte+3 table, trailing EOS)."""
    return [b + BYTE_OFFSET for b in text.encode("utf-8")] + [EOS_ID]


def decode(token_ids: list[int]) -> str:
    """Token ids -> text; stops at EOS, maps id-3 back to a byte."""
    out = bytearray()
    for token in token_ids:
        if token == EOS_ID:
            break
        if token in (PAD_ID, UNK_ID):
            continue
        out.append((token - BYTE_OFFSET) % 256)
    return out.decode("utf-8", errors="replace")
