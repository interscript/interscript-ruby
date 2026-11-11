"""ISC-WF-0 golden capture additivity — the Python mirror of
interscript-rs ``tests/golden_capture.rs`` and interscript-ts
``test/golden-isc-wf0.test.ts``.

Replays every row of the RS-captured golden file
(``interscript-rs/tests/golden/isc-wf0.jsonl``) through THIS runtime —
parse the sibling maps/libs ``.isc`` corpus, compile, execute — and
requires byte-identical output on every row (rows of maps listed in
the adopting manifest ``tests/golden/adopting-maps.txt`` are exempt).
The golden is the cross-runtime contract: a delta here is a runtime
regression (or a newly-fixed divergence being adopted into the
golden).

Skips when the sibling interscript-rs / maps checkouts are missing
(``GOLDEN_ROOT`` overrides the sibling root, mirroring the ts test).
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from interscript.executor import execute_stage
from interscript.isc import isc_to_compiled_map, parse_isc

REPO_ROOT = Path(__file__).resolve().parents[3]
SIBLING_ROOT = Path(os.environ.get("GOLDEN_ROOT", str(REPO_ROOT)))
GOLDEN = SIBLING_ROOT / "interscript-rs" / "tests" / "golden" / "isc-wf0.jsonl"
ADOPTING = SIBLING_ROOT / "interscript-rs" / "tests" / "golden" / "adopting-maps.txt"
MAPS_DIR = SIBLING_ROOT / "maps" / "maps"
LIBS_DIR = SIBLING_ROOT / "maps" / "libs"


def _sibling_checkouts_present() -> bool:
    return GOLDEN.is_file() and MAPS_DIR.is_dir()


def _load_adopting() -> set[str]:
    if not ADOPTING.is_file():
        return set()
    return {
        line.strip()
        for line in ADOPTING.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    }


def _build_corpus() -> tuple[dict[str, object], object]:
    """Parse + compile every corpus .isc; dependencies (and WF-1
    ``use alias.<ruleset>`` expansion) resolve lazily against the same
    corpus. libs first: the parser validates ``dependency`` targets
    eagerly, and system maps declare dependencies on the libraries
    (e.g. thai-latn)."""
    docs: dict[str, object] = {}

    def resolve_dependency(target: str):
        return docs.get(target)

    for directory in (LIBS_DIR, MAPS_DIR):
        for path in sorted(directory.glob("*.isc")):
            docs[path.stem] = parse_isc(
                path.read_text(encoding="utf-8"),
                filename=str(path),
                resolve_dependency=resolve_dependency,
            )
    compiled = {stem: isc_to_compiled_map(doc) for stem, doc in docs.items()}

    class _Resolver:
        """MapResolver over the in-memory corpus (the MapLoader protocol:
        .load(system_code))."""

        def load(self, system_code: str):
            return compiled[system_code]

    return compiled, _Resolver()


@pytest.mark.skipif(
    not _sibling_checkouts_present(),
    reason="skip: golden capture or sibling maps checkout missing",
)
def test_golden_capture_additivity() -> None:
    rows = [
        json.loads(line)
        for line in GOLDEN.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert rows, "golden file has no rows"
    compiled, resolver = _build_corpus()
    adopting = _load_adopting()

    deltas: list[str] = []
    failed_maps: set[str] = set()
    exempt = 0
    for row in rows:
        map_id = row["map"]
        if map_id in adopting:
            exempt += 1
            continue
        compiled_map = compiled.get(map_id)
        if compiled_map is None:
            got = "\x00error:map not found"
        else:
            try:
                got = execute_stage(compiled_map, "main", row["src"], resolver)
            except Exception as exc:  # noqa: BLE001 — mirror the ts/rs gates
                got = f"\x00error:{exc}"
        if got == row["out"]:
            continue
        failed_maps.add(map_id)
        if len(deltas) < 10:
            deltas.append(
                f"{map_id}: {row['src']!r} -> {got!r} (golden {row['out']!r})"
            )

    assert not failed_maps, (
        f"golden divergence on {len(failed_maps)} map(s); "
        f"first deltas:\n" + "\n".join(deltas)
    )
    assert len(rows) - exempt > 0
