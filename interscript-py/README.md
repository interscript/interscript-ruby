# interscript-py

Python runtime for [Interscript](https://www.interscript.org) —
deterministic transliteration over the interscript map corpus (300+
authority-backed systems: BGN/PCGN, ISO, UN, ALA-LC, ODNI, ICAO, DIN,
and others), plus the ByT5 model layer for the phonological maps.

License: BSD-3-Clause.

## Architecture

```
                         interscript/maps (350+ .isc sources)
                                        |
                     maps CI: scripts/build-json-ir-artifact.mjs
                     (interscript-ts parseIsc + iscToCompiledMap)
                                        v
             COMPILED JSON-IR ARTIFACT   interscript.maps.ir.v1
             manifest.json + SHA256SUMS + maps/<system>.json
                                        |
             GitHub Releases (interscript-maps-ir-<version>.tar.gz
                              + .sha256 sidecar)  <- canonical channel
                                        |
             +--------------------------+---------------------------+
             |                          |                           |
        interscript-ts            interscript-py (this repo)     (ruby: .isc DSL)
        (reference consumer)      loader + executor
```

This package **executes the compiled JSON-IR maps** — the same artifact
the TypeScript runtime consumes. It does NOT parse `.isc` sources; the
compiler is the maps repo's CI (single source of truth, shared by every
runtime, which is what makes cross-runtime byte-identity checkable).

### Map execution (now)

- `interscript.loader` — artifact directories (and release tarballs):
  `manifest.json`, `SHA256SUMS` verification, per-system JSON decode,
  in-memory cache, dependency resolution (`posix`, `unicode`,
  `var-Cyrl`, `var-kor` libs are compiled into the artifact).
- `interscript.executor` — stage/rule execution, a faithful port of
  interscript-ts's `runtime/`:
  - `sub` rules compile to regex with lookaround constraints
    (`before`/`after`/`not_before`/`not_after`) and `$n` capture
    templates,
  - `parallel` blocks take the whole block down ONE of two paths
    (matching Ruby): trie-based single-pass replace when every rule is
    literal-expandable, else ONE megaregexp alternation sorted
    longest-first,
  - `run` resolves in-map stages or dependency maps by system code,
  - `funcall` dispatches to the builtin registry (`upcase`, `downcase`,
    `title_case`, `separate`, `compose`, `decompose`).
- Regexes run on the third-party `regex` module (Unicode categories
  `\p{L}`, variable-width lookbehind; stdlib `re` supports neither).

### Model layer (`interscript.models`, optional extra)

Fold-in of the house ONNX runtime (interscript-ml — now superseded by
the `secryst` package, which stays the canonical model runtime; this
subpackage keeps the maps+models-in-one-install surface):

- `tokens` — the canonical ByT5 byte table: ids are `byte + 3` with a
  trailing EOS (id 1). Raw `text.encode()` is NOT the id sequence.
- `loader` — IMF v1 zip: manifest parsing + per-member sha256
  verification (corrupt downloads fail loudly).
- `registry` — models index (`index-vN`) resolve + cached download,
  sha256-verified, GitHub Releases only.
- `model` — `Model.load(path_or_id)` with single-row-greedy decode: one
  encoder row per call (no padding, no attention mask), greedy argmax
  until EOS, 512-step cap. Batched decode on unmasked encoders corrupts
  encoder states and is not part of the contract; beam search lives in
  `secryst`.
- `model.mount("secryst")` registers the model as the handler for a
  map's ML funcall, so phonological maps execute end to end.

Install with `pip install interscript-py[ml]`.

### parsanol-python parse path (later)

The work order's full design runs maps via
[parsanol-python](https://github.com/parsanol/parsanol-python)
(`~/src/parsanol/parsanol-python`), which parses the `.isc` DSL
directly. This package deliberately starts with the compiled-IR path
(CI-proven, identical to the TS runtime, zero parser drift). The
parsanol-python parse path is the follow-up: a second loader strategy
(`iscStrategy` in TS terms) feeding the same executor, so both paths
share rule execution and conformance fixtures. The `Runtime` /
`MapLoader` strategy composition is already shaped for this (add a
resolver, don't touch the executor).

## Install and obtain the maps artifact

The compiled artifact is a release artifact — never bundled:

```sh
pip install interscript-py            # or: pip install -e interscript-py[ml,dev]
python -m interscript.artifact_fetch  # latest release -> ~/.cache/interscript/maps-ir/<version>/
```

or point the loader at an artifact directory you already have:

```python
import interscript

interscript.add_load_path("/path/to/interscript-maps-ir")
interscript.transliterate("un-bul-Cyrl-Latn-1977", "нос Бяга БЯГА")
# -> 'nos Byaga BYAGA'
```

`$INTERSCRIPT_MAPS_IR` (colon-separated directories) is honored
automatically. To rebuild the artifact locally from the maps repo:

```sh
scripts/build_maps_ir.sh ~/src/interscript/maps ~/src/interscript/interscript-ts /tmp/isir
```

## Conformance

The acceptance gate is byte-exact output (no normalization, no CER
tolerance), on two fixture sets:

1. **Maps corpus embedded tests** — every `.isc` file ships a
   `tests { "src" -> "out" }` block. `pytest` replays the bundled
   265-map subset of compiled maps against those rows; point
   `$INTERSCRIPT_MAPS_IR` at a full artifact to run all 315
   test-bearing maps. Two maps are expected-divergent (see
   `tests/test_embedded_map_tests.py::KNOWN_IR_LIMITATION`): the
   TypeScript reference produces the identical bytes — the rows need
   Ruby-only string-alias-as-char-class semantics / the pronunciation
   lexicon layer, which the compiled IR cannot express.
2. **Frozen model vectors** (`interscript-models/conformance/`, six
   families). `interscript.conformance.run_vectors` replays a family's
   vectors through a local zip, byte-exact. Needs `interscript-py[ml]`
   and a model zip: set `$INTERSCRIPT_MODEL_ZIPS` to a directory of
   zips, or let the registry resolve ids (downloads + sha256-verifies
   into `~/.cache/interscript`). `tha-g2p-lex-1.0` currently has no
   release asset to fetch — its family skips until one is published.

```sh
make test        # map runtime: unit + embedded corpus (bundled subset)
make test-full   # + full artifact via $INTERSCRIPT_MAPS_IR (set in the target)
make test-ml     # + frozen model vector families that have local zips
make lint        # ruff if available
```

## Layout

```
src/interscript/
  __init__.py        public API: add_load_path, map_list, transliterate, Runtime
  _ir_types.py       typed mirror of the JSON-IR wire format (strict decode)
  loader.py          artifact dirs, SHA256SUMS verify, tarball extraction
  context.py         execution context: alias + dependency resolution
  items.py           Item -> regex/literal compilation (port of compile-item.ts)
  executor.py        rule executors (port of executor.ts + interpreter.ts)
  stdlib.py          trie parallel replace, megaregexp, builtin functions
  conformance.py     frozen-vector harness (byte-exact)
  artifact_fetch.py  `python -m interscript.artifact_fetch` (GH Releases)
  models/            model layer (optional extra): tokens, loader, registry, model
tests/
  data/maps-ir/      curated 265-map compiled subset (manifest + SHA256SUMS)
```
