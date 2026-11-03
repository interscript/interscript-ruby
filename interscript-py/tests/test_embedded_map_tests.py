# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Byte-identical replay of the maps corpus' OWN embedded tests.

Every .isc file in interscript/maps carries a `tests { "src" -> "out" }`
block; the Ruby and TS runtimes gate on these. Here each bundled
compiled map is paired with its source block and executed — output must
match byte-exactly, no normalization, no tolerance.

The bundled artifact is a curated 263-map subset (see data/maps-ir);
point `$INTERSCRIPT_MAPS_IR` at a full artifact directory to run the
whole corpus (315 test-bearing maps).
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

import interscript

TEST_BLOCK_RE = re.compile(r"tests \{(.*)\n\}", re.DOTALL)
TEST_ROW_RE = re.compile(r'"((?:[^"\\]|\\.)*)"\s*->\s*"((?:[^"\\]|\\.)*)"\s*(?:#.*)?$')

ESCAPES_MAP = {
    "n": "\n",
    "t": "\t",
    "r": "\r",
    '"': '"',
    "\\": "\\",
}


def _unescape(text: str) -> str:
    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            if nxt == "u" and i + 5 < len(text):
                out.append(chr(int(text[i + 2 : i + 6], 16)))
                i += 6
                continue
            out.append(ESCAPES_MAP.get(nxt, nxt))
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def extract_tests(isc_path: Path) -> list[tuple[str, str]]:
    """Pull (src, expected) rows out of a .isc source's tests blocks."""
    rows: list[tuple[str, str]] = []
    for block in TEST_BLOCK_RE.finditer(isc_path.read_text(encoding="utf-8")):
        for line in block.group(1).splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            m = TEST_ROW_RE.match(stripped)
            if m:
                rows.append((_unescape(m.group(1)), _unescape(m.group(2))))
    return rows


def bundled_systems(artifact_dir: Path) -> list[str]:
    return sorted(p.stem for p in (artifact_dir / "maps").glob("*.json"))


def test_bundled_subset_has_maps(artifact_dir):
    assert len(bundled_systems(artifact_dir)) >= 200


def _full_artifact_from_env() -> Path | None:
    import os

    env = os.environ.get("INTERSCRIPT_MAPS_IR", "")
    for part in env.split(":") if env else []:
        p = Path(part).expanduser()
        if p.is_dir():
            return p
    return None


def _systems_for_collection() -> list[str]:
    """Prefer a full artifact from `$INTERSCRIPT_MAPS_IR` (CI), else the
    bundled subset — evaluated at collection time."""
    root = _full_artifact_from_env() or (
        Path(__file__).parent / "data" / "maps-ir"
    )
    if not (root / "maps").is_dir():
        return []
    return sorted(p.stem for p in (root / "maps").glob("*.json"))


# Maps whose embedded tests are NOT satisfiable from the compiled IR by
# ANY runtime — verified by instrumenting the TypeScript reference on the
# same artifact (it produces the identical "wrong" bytes):
#
# - alalc-ell-Grek-Latn-2010: the unicode lib's `greek` alias is a plain
#   STRING of all greek chars; Ruby's Any(String) means char-class, the
#   converter emits {kind:"string"} and both TS and py compile `any(...)`
#   over it as a literal sequence, so the gamma-palatalization context
#   rules never fire (5/242 rows).
# - bgnpcgn-tha-Thai-Latn-2002: pronunciation-dependent rows the map's
#   own notes route through the pronunciation-lexicon layer
#   (carrier-interleaved compounds are WO80-pending) (6/12 rows).
KNOWN_IR_LIMITATION = {
    "alalc-ell-Grek-Latn-2010",
    "bgnpcgn-tha-Thai-Latn-2002",
}


@pytest.mark.parametrize("system", _systems_for_collection())
def test_embedded_map_tests(system, artifact_dir, maps_src):
    isc = maps_src / "maps" / f"{system}.isc"
    if not isc.is_file():  # lib maps (posix, unicode, ...) have no .isc in maps/
        lib = maps_src / "libs" / f"{system}.isc"
        if not lib.is_file():
            pytest.skip(f"no .isc source for {system}")
        isc = lib
    rows = extract_tests(isc)
    if not rows:
        pytest.skip(f"{system}: no parsable test rows")
    if system in KNOWN_IR_LIMITATION:
        pytest.skip(
            f"{system}: embedded rows need semantics the compiled IR "
            "cannot express (string alias as char class / lexicon layer); "
            "TS reference diverges identically"
        )
    rt = interscript.Runtime([artifact_dir])
    failures = []
    for src, expected in rows:
        actual = rt.transliterate(system, src)
        if actual != expected:
            failures.append((src, expected, actual))
    assert not failures, (
        f"{system}: {len(failures)}/{len(rows)} embedded tests differ:\n"
        + "\n".join(
            f"  src={s!r}\n  want={e!r}\n  got ={a!r}" for s, e, a in failures[:8]
        )
    )
