"""WO20 reverse-mode golden capture additivity — the Python mirror of
interscript-rs ``tests/golden_reverse_capture.rs``, the ruby gate
(``tools/isc_wf1_golden_gate.rb --reverse``) and interscript-ts
``test/golden-isc-reverse.test.ts``.

Replays every row of the RS-captured reverse golden file
(``interscript-rs/tests/golden/isc-reverse.jsonl``) through THIS
runtime — parse the sibling maps/libs corpus plus the rs reverse
fixtures, compile, REVERSE the map, execute the reversed main stage on
the row's src — and requires byte-identical output on every row. The
golden was captured once by ``iscrs capture --reverse``; a delta here
is a reverse-parity regression. No adopting-set exemption: the reverse
golden has no adoption flow. An execution error replays as ``null``,
the canonical marker the rs capture records.

The rs reverse fixtures (``tests/reverse_maps``, siblings of the
golden file) join the corpus AFTER it, first-wins, so a corpus map
shadows a same-named fixture exactly like the capture's load path.

Skips when the sibling interscript-rs / maps checkouts are missing
(``GOLDEN_ROOT`` overrides the sibling root, mirroring the forward
gate).
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from interscript.executor import execute_stage
from interscript.isc import isc_to_compiled_map, parse_isc
from interscript.reverse import reverse_map

REPO_ROOT = Path(__file__).resolve().parents[3]
SIBLING_ROOT = Path(os.environ.get("GOLDEN_ROOT", str(REPO_ROOT)))
GOLDEN = SIBLING_ROOT / "interscript-rs" / "tests" / "golden" / "isc-reverse.jsonl"
MAPS_DIR = SIBLING_ROOT / "maps" / "maps"
LIBS_DIR = SIBLING_ROOT / "maps" / "libs"
FIXTURES_DIR = SIBLING_ROOT / "interscript-rs" / "tests" / "reverse_maps"


def _sibling_checkouts_present() -> bool:
    return GOLDEN.is_file() and MAPS_DIR.is_dir()


def _build_corpus() -> tuple[dict[str, object], object]:
    """Parse + compile every corpus .isc (libs first: dependency
    targets validate eagerly) then the rs reverse fixtures FIRST-WINS,
    so a corpus map shadows a same-named fixture exactly like the
    capture's load path. Dependencies resolve lazily against the same
    corpus."""
    docs: dict[str, object] = {}

    def resolve_dependency(target: str):
        return docs.get(target)

    for directory in (LIBS_DIR, MAPS_DIR, FIXTURES_DIR):
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.isc")):
            if path.stem in docs:
                continue
            docs[path.stem] = parse_isc(
                path.read_text(encoding="utf-8"),
                filename=str(path),
                resolve_dependency=resolve_dependency,
            )
    compiled = {stem: isc_to_compiled_map(doc) for stem, doc in docs.items()}
    return compiled


@pytest.mark.skipif(
    not _sibling_checkouts_present(),
    reason="skip: reverse golden capture or sibling maps checkout missing",
)
def test_golden_reverse_capture_additivity() -> None:
    rows = [
        json.loads(line)
        for line in GOLDEN.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert rows, "reverse golden file has no rows"
    compiled = _build_corpus()

    # rs reverse_document reverses the dependency CLOSURE with the
    # parent (ruby Dependency#reverse parity). The compiled IR carries
    # dependency names, not documents, so the replay must serve
    # reversed dependency maps to the run rules — Runtime.reverse's
    # _ReversedDependencyResolver flow. Replaying reverse_map against
    # forward deps made every run-carrying reverse doc execute the
    # FORWARD dependency stage (the WO20 91-map identity-output family:
    # alalc-rus-2012's "Azov" etc.).
    reversed_closure: dict[str, tuple[object, dict[str, object]]] = {}

    def _reversed_closure(name: str) -> tuple[object, dict[str, object]]:
        if name in reversed_closure:
            return reversed_closure[name]
        map_ = compiled[name]
        revs: dict[str, object] = {}

        def collect(m: object) -> None:
            for dep in m.dependencies:  # type: ignore[union-attr]
                if dep in revs:
                    continue
                dep_map = compiled[dep]
                revs[dep] = reverse_map(dep_map)
                collect(dep_map)

        collect(map_)
        entry = (reverse_map(map_), revs)
        reversed_closure[name] = entry
        return entry

    class _ReversedResolver:
        """Serves reversed dependency documents under their forward
        names (run rules reference the forward names)."""

        def __init__(self, revs: dict[str, object]) -> None:
            self._revs = revs

        def load(self, system_code: str):
            return self._revs[system_code]

    deltas: list[str] = []
    failed_maps: set[str] = set()
    checked = 0
    for row in rows:
        map_id = row["map"]
        compiled_map = compiled.get(map_id)
        if compiled_map is None:
            got = "null"
        else:
            try:
                reversed_map, revs = _reversed_closure(map_id)
                got = execute_stage(reversed_map, "main", row["src"], _ReversedResolver(revs))
            except Exception:  # noqa: BLE001 — mirror the rs/ts/ruby gates
                got = "null"
        checked += 1
        if got == row["out"]:
            continue
        failed_maps.add(map_id)
        if len(deltas) < 10:
            deltas.append(
                f"{map_id}: {row['src']!r} -> {got!r} (golden {row['out']!r})"
            )

    assert not failed_maps, (
        f"reverse golden divergence on {len(failed_maps)} map(s); "
        f"first deltas:\n" + "\n".join(deltas)
    )
    assert checked == len(rows)
