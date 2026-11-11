# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""py-vs-py ISC parse parity driver — the swap gate for WO17 step 4b.

Parses every corpus file (maps/*.isc + libs/*.isc of an interscript/maps
checkout) with TWO python ISC parsers and proves they agree:

    - HAND:  the replaced hand-written recursive-descent parser,
      materialized from a git revision of this repository (default:
      HEAD — run this BEFORE committing the parser swap; pass
      --hand-rev <parent-of-swap> after).
    - GENERATED: the grammar-driven parser shipped in
      src/interscript/grammar/ (what interscript.isc.parse_isc is now).

Every parsed document (dependencies resolved against the same corpus,
each side with its own parser) is projected onto the maps
scripts/parse-parity.mjs canonical schema (the py normalizer: constraint
kinds re-sorted into SubRule's fixed fields, `none` lowered to "").
The driver reports TWO numbers:

    - canonical: identical under the canonical schema (the official
      judge — the same projection the cross-runtime harness compares).
    - raw: identical field-for-field INCLUDING from_source and the
      written constraint order (strictest swap-safety bar; a superset
      of the canonical comparison).

Usage:
    python scripts/parse_parity_py.py [--maps-root <interscript-maps>]
        [--hand-rev <git-rev>] [--json <report.json>] [--only <substring>]
        [--verbose]

Exit code 0 only when EVERY corpus file passes BOTH projections.
"""

from __future__ import annotations

import argparse
import dataclasses
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PY_SRC = Path(__file__).resolve().parents[1] / "src"

sys.path.insert(0, str(PY_SRC))

from interscript.isc import parse_isc as generated_parse_isc

# The py normalizer's keyword tables (mirrored from maps
# scripts/parse-parity.mjs — identical to both parsers').
PRIMITIVES = frozenset(
    ["boundary", "line_start", "line_end", "word_boundary", "space", "non_boundary"]
)
FUNCTIONS = frozenset(["upcase", "downcase", "title_case", "reverse", "strip", "swapcase"])
PY_CONSTRAINT_ORDER = ["before", "after", "not_before", "not_after"]


# ---------------------------------------------------------------------------
# Hand parser materialization — the replaced isc.py from a git revision
# ---------------------------------------------------------------------------


def load_hand_parser(repo_root: Path, rev: str):
    """Materialize the hand isc.py at `rev` into a temp package (its
    siblings _ir_types.py / errors.py are copied from the current tree —
    they are identical across the swap) and import it."""
    def show(path: str) -> str:
        out = subprocess.run(
            ["git", "-C", str(repo_root), "show", f"{rev}:{path}"],
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout

    isc_src = show("interscript-py/src/interscript/isc.py")
    if "from .grammar.isc_parser import" in isc_src:
        raise SystemExit(
            f"parse_parity_py: rev {rev!r} already carries the generated parser — "
            f"pass --hand-rev <revision-before-the-swap>"
        )
    tmp = Path(tempfile.mkdtemp(prefix="hand-isc-"))
    pkg = tmp / "hand_isc_pkg"
    pkg.mkdir()
    (pkg / "__init__.py").write_text("", encoding="utf-8")
    (pkg / "isc.py").write_text(isc_src, encoding="utf-8")
    for sibling in ("_ir_types.py", "errors.py"):
        (pkg / sibling).write_text(
            (PY_SRC / "interscript" / sibling).read_text(encoding="utf-8"),
            encoding="utf-8",
        )
    spec = importlib.util.spec_from_file_location(
        "hand_isc_pkg.isc", pkg / "isc.py",
        submodule_search_locations=[str(pkg)],
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["hand_isc_pkg"] = type(sys)("hand_isc_pkg")
    sys.modules["hand_isc_pkg"].__path__ = [str(pkg)]
    sys.modules["hand_isc_pkg.isc"] = module
    spec.loader.exec_module(module)  # type: ignore[union-attr]
    return module.parse_isc


# ---------------------------------------------------------------------------
# Canonical schema — port of maps scripts/parse-parity.mjs's py normalizer
# ---------------------------------------------------------------------------


def jsonable(x):
    if dataclasses.is_dataclass(x) and not isinstance(x, type):
        d = {"__kind__": type(x).__name__}
        for f in dataclasses.fields(x):
            d[f.name] = jsonable(getattr(x, f.name))
        return d
    if isinstance(x, (list, tuple)):
        return [jsonable(v) for v in x]
    if isinstance(x, dict):
        return {k: jsonable(v) for k, v in x.items()}
    return x


def canon_item(it):
    if not isinstance(it, dict):
        return {"t": "shape", "raw": str(it)}
    kind = it["__kind__"]
    if kind == "StringItem":
        return {"t": "s", "v": it["value"]}
    if kind == "AliasItem":
        if it["name"] in PRIMITIVES:
            return {"t": "prim", "name": it["name"]}
        if it["name"] in FUNCTIONS:
            return {"t": "fn", "name": it["name"]}
        return {"t": "alias", "name": it["name"]}
    if kind == "CaptureGroupItem":
        return {"t": "cap", "inner": canon_item(it["data"])}
    if kind == "CaptureRefItem":
        return {"t": "ref", "id": it["id"]}
    if kind == "AnyItem":
        return {"t": "any", "of": [canon_item(i) for i in it["of"]]}
    if kind == "AnyCharClassItem":
        if it["range"]:
            return {"t": "range", "lo": it["range"][0], "hi": it["range"][1]}
        if it["chars"]:
            return {"t": "any", "of": [{"t": "s", "v": c} for c in it["chars"]]}
        return {"t": "shape", "raw": "any_char_class with neither range nor chars"}
    if kind == "GroupItem":
        return {"t": "cat", "parts": [canon_item(i) for i in it["items"]]}
    if kind == "RepeatItem":
        if it["min"] == 0 and it["max"] == 1:
            return {"t": "maybe", "inner": canon_item(it["item"])}
        if it["min"] == 1 and it["max"] is None:
            return {"t": "some", "inner": canon_item(it["item"])}
        return {"t": "shape", "raw": f"repeat min={it['min']} max={it['max']}"}
    if kind == "FuncallInline":
        return {"t": "fn", "name": it["name"]}
    if kind == "StageItem":
        return {"t": "stage_ref", "name": it["name"]}
    return {"t": "shape", "raw": json.dumps(it)}


def canon_rule(r):
    return {
        "from": canon_item(r["from_"]),
        "to": canon_item(r["to"]),
        "constraints": [
            {"kind": k, "item": canon_item(r[k])} for k in PY_CONSTRAINT_ORDER if r[k] is not None
        ],
        **({"when": list(r["when"])} if r["when"] else {}),
    }


def canon_stage_item(it):
    kind = it["__kind__"]
    if kind == "ParsedRule":
        return {"k": "rule", "rule": canon_rule(it["rule"]), "fromSource": it["from_source"]}
    if kind == "ParallelBlock" or kind == "SequenceBlock":
        return {
            "k": "parallel" if kind == "ParallelBlock" else "sequence",
            "rules": [canon_rule(r["rule"]) for r in it["rules"]],
        }
    if kind == "RunItem":
        out = {"k": "run", "stage": it["stage"]}
        if it["dependency"]:
            out["dependency"] = it["dependency"]
        return out
    if kind == "FuncallRule":
        if it["name"] == "separate":
            sep = (it.get("kwargs") or {}).get("separator")
            return {"k": "separate", **({"separator": {"t": "s", "v": sep}} if sep is not None else {})}
        if it["name"] == "compose":
            return {"k": "compose"}
        if it["name"] == "decompose":
            return {"k": "decompose"}
        if it["name"] in FUNCTIONS:
            return {"k": "string_case", "op": it["name"]}
        return {"k": "funcall", "name": it["name"], "kwargs": dict(it.get("kwargs") or {})}
    return {"k": "shape", "raw": json.dumps(it)}


def canon_doc(doc):
    return {
        "systemCode": doc.system_code,
        "metadata": jsonable(doc.metadata) or {},
        "tests": [
            {"input": t.input, "expected": t.expected, **({"note": t.note} if t.note is not None else {})}
            for t in doc.tests
        ],
        "dependencies": [
            {"target": d.target, **({"alias": d.alias_name} if d.alias_name is not None else {})}
            for d in doc.dependencies
        ],
        "aliases": [{"name": a[0], "item": canon_item(a[1])} for a in doc.aliases],
        **({"languages": list(doc.languages)} if doc.languages else {}),
        "stages": [{"name": s.name, "body": [canon_stage_item(jsonable(i)) for i in s.items]} for s in doc.stages],
        "rulesets": {
            name: [canon_stage_item(jsonable(i)) for i in body]
            for name, body in doc.rulesets.items()
        },
    }


# ---------------------------------------------------------------------------
# Comparison with path reporting
# ---------------------------------------------------------------------------


def walk(a, b, path, section, divergences):
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            divergences.append({"kind": section, "path": path, "hand": f"len={len(a)}", "gen": f"len={len(b)}"})
        for i in range(min(len(a), len(b))):
            walk(a[i], b[i], f"{path}[{i}]", section, divergences)
        return
    if not isinstance(a, dict) or not isinstance(b, dict):
        if a != b:
            divergences.append({"kind": section, "path": path, "hand": json.dumps(a, ensure_ascii=False)[:400], "gen": json.dumps(b, ensure_ascii=False)[:400]})
        return
    for key in set(a) | set(b):
        if key not in a or key not in b:
            divergences.append({"kind": section, "path": f"{path}.{key}", "hand": json.dumps(a.get(key), ensure_ascii=False)[:400], "gen": json.dumps(b.get(key), ensure_ascii=False)[:400]})
            continue
        walk(a[key], b[key], f"{path}.{key}", section, divergences)


def compare_docs(a, b, sections, divergences):
    for section in sections:
        if section not in a and section not in b:
            continue
        if section not in a or section not in b:
            divergences.append({"kind": section, "path": section, "hand": json.dumps(a.get(section)), "gen": json.dumps(b.get(section))})
            continue
        walk(a[section], b[section], section, section, divergences)


CANON_SECTIONS = ["systemCode", "metadata", "tests", "dependencies", "aliases", "languages", "stages", "rulesets"]


def parse_with(parse_fn, source, path, dep_index, cache):
    def resolver(target):
        if target in cache:
            return cache[target]
        entry = dep_index.get(target)
        if entry is None:
            return None
        with open(entry, encoding="utf-8") as fh:
            doc = parse_fn(fh.read(), entry, resolve_dependency=resolver)
        cache[target] = doc
        return doc

    with open(path, encoding="utf-8") as fh:
        source = fh.read()
    return parse_fn(source, path, resolve_dependency=resolver)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--maps-root", default=str(REPO_ROOT.parent / "maps"))
    ap.add_argument("--hand-rev", default="HEAD")
    ap.add_argument("--json", dest="json_out")
    ap.add_argument("--only")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    maps_root = Path(args.maps_root).resolve()
    files = []
    dep_index = {}
    for sub in ("maps", "libs"):
        d = maps_root / sub
        for f in sorted(d.iterdir()):
            if f.suffix == ".isc":
                files.append({"rel": f"{sub}/{f.name}", "path": f})
                dep_index[f.stem] = f
    if args.only:
        files = [f for f in files if args.only in f["rel"]]
    if not files:
        print(f"parse_parity_py: no corpus files under {maps_root}/maps and /libs", file=sys.stderr)
        return 2

    hand_parse = load_hand_parser(REPO_ROOT, args.hand_rev)

    hand_cache: dict = {}
    gen_cache: dict = {}

    reports = []
    canon_pass = 0
    raw_pass = 0
    for f in files:
        divergences_canon = []
        divergences_raw = []
        try:
            hand_doc = parse_with(hand_parse, "", f["path"], dep_index, hand_cache)
        except Exception as e:  # noqa: BLE001
            hand_doc = e
        try:
            gen_doc = parse_with(generated_parse_isc, "", f["path"], dep_index, gen_cache)
        except Exception as e:  # noqa: BLE001
            gen_doc = e

        if isinstance(hand_doc, Exception) or isinstance(gen_doc, Exception):
            divergences_canon.append({
                "kind": "error",
                "path": "parse",
                "hand": type(hand_doc).__name__ + ": " + str(hand_doc) if isinstance(hand_doc, Exception) else "ok",
                "gen": type(gen_doc).__name__ + ": " + str(gen_doc) if isinstance(gen_doc, Exception) else "ok",
            })
            status = "FAIL"
        else:
            compare_docs(canon_doc(hand_doc), canon_doc(gen_doc), CANON_SECTIONS, divergences_canon)
            compare_docs(
                jsonable(hand_doc), jsonable(gen_doc),
                ["system_code", "metadata", "tests", "aliases", "stages", "dependencies", "languages", "rulesets"],
                divergences_raw,
            )
        canon_ok = not divergences_canon
        raw_ok = not divergences_raw
        canon_pass += canon_ok
        raw_pass += raw_ok
        status = "PASS" if (canon_ok and raw_ok) else "FAIL"
        reports.append({
            "path": f["rel"], "status": status,
            "canonical": "PASS" if canon_ok else divergences_canon,
            "raw": "PASS" if raw_ok else divergences_raw,
        })
        if status == "PASS":
            print(f"{f['rel']} PASS")
        else:
            first = (divergences_canon or divergences_raw)[0]
            print(f"{f['rel']} FAIL canon={len(divergences_canon)} raw={len(divergences_raw)}; first: {first['kind']} @ {first['path']}")
            if args.verbose:
                for d in (divergences_canon + divergences_raw)[:12]:
                    print(f"    {d['kind']} @ {d['path']}\n      hand: {d['hand']}\n      gen:  {d['gen']}")

    print(
        f"parity: canonical {canon_pass}/{len(files)}; raw {raw_pass}/{len(files)} "
        f"(hand rev {args.hand_rev})"
    )
    if args.json_out:
        Path(args.json_out).write_text(json.dumps({"files": reports, "handRev": args.hand_rev}, indent=2), encoding="utf-8")
    return 0 if (canon_pass == len(files) and raw_pass == len(files)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
