# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Corpus parse timing for the generated ISC parser (perf work harness).

Parses every corpus file (maps/*.isc + libs/*.isc) with the generated
parser only, dependencies resolved from the same corpus, and reports the
total wall time. One run = one full corpus pass; invoke N times for a
median. --profile <substring> cProfiles a single file instead.

Usage:
    python scripts/time_corpus_py.py                # one corpus pass
    python scripts/time_corpus_py.py --repeat 3     # three passes, median
    python scripts/time_corpus_py.py --profile var-kor
"""

from __future__ import annotations

import argparse
import cProfile
import pstats
import statistics
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PY_SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(PY_SRC))

from interscript.isc import parse_isc


def corpus_files(maps_root: Path):
    files = []
    dep_index = {}
    for sub in ("maps", "libs"):
        d = maps_root / sub
        for f in sorted(d.iterdir()):
            if f.suffix == ".isc":
                files.append({"rel": f"{sub}/{f.name}", "path": f})
                dep_index[f.stem] = f
    return files, dep_index


def one_pass(files, dep_index):
    cache: dict = {}

    def resolver(target):
        if target in cache:
            return cache[target]
        entry = dep_index.get(target)
        if entry is None:
            return None
        with open(entry, encoding="utf-8") as fh:
            doc = parse_isc(fh.read(), entry, resolve_dependency=resolver)
        cache[target] = doc
        return doc

    t0 = time.perf_counter()
    for f in files:
        with open(f["path"], encoding="utf-8") as fh:
            parse_isc(fh.read(), f["path"], resolve_dependency=resolver)
    return time.perf_counter() - t0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--maps-root", default=str(REPO_ROOT.parent / "maps"))
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--profile")
    args = ap.parse_args()

    maps_root = Path(args.maps_root).resolve()
    files, dep_index = corpus_files(maps_root)
    if not files:
        print(f"no corpus files under {maps_root}", file=sys.stderr)
        return 2

    if args.profile:
        target = next(f for f in files if args.profile in f["rel"])
        cache: dict = {}

        def resolver(target):
            if target in cache:
                return cache[target]
            entry = dep_index.get(target)
            if entry is None:
                return None
            with open(entry, encoding="utf-8") as fh:
                doc = parse_isc(fh.read(), entry, resolve_dependency=resolver)
            cache[target] = doc
            return doc

        with open(target["path"], encoding="utf-8") as fh:
            source = fh.read()
        # warm the compiled grammar + cache first, profile the top-level file alone
        one_pass(files, dep_index)
        pr = cProfile.Profile()
        pr.enable()
        parse_isc(source, target["path"], resolve_dependency=resolver)
        pr.disable()
        stats = pstats.Stats(pr)
        stats.sort_stats("cumulative")
        print(f"=== cProfile {target['rel']} ({len(source)} chars) ===")
        stats.print_stats(28)
        stats.sort_stats("tottime")
        print("=== by tottime ===")
        stats.print_stats(28)
        return 0

    times = [one_pass(files, dep_index) for _ in range(args.repeat)]
    for i, t in enumerate(times):
        print(f"pass {i + 1}: {t:.2f} s")
    print(f"corpus files: {len(files)}; median: {statistics.median(times):.2f} s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
