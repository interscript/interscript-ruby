# 04 — TS runtime: ISC loader strategy

## Priority: P1

## Status: COMPLETE

## Problem
The TS runtime has load strategies for JSON IR (`bundledStrategy`,
`httpStrategy`). Need a new strategy that loads `.isc` source files
and parses them on the fly.

## Implementation

Two strategies in `interscript-ts/src/isc/loader.ts`:

- **`iscStrategy(opts)`** — async; fetches `.isc` files from a base URL (browser-side via `fetch`). Falls back to bundled sources if provided.
- **`iscBundledStrategy(sources)`** — sync; takes a `{code: source}` dictionary (Node.js `readFileSync` results, or bundled at build time).

Both call `parseIsc(source, filename)` then `iscToCompiledMap(doc)` then `normaliseMap(json)` to produce the runtime's `CompiledMap` shape.

```typescript
import { iscStrategy, iscBundledStrategy } from "interscript-ts/isc"

// Browser: fetch .isc files on-demand
configure({ strategies: [iscStrategy({ baseUrl: "/maps" })] })

// Node/pre-bundled: sync lookup
configure({ strategies: [iscBundledStrategy(sources)] })
```

### Backward compatibility
Existing JSON IR strategies (`bundledStrategy`, `httpStrategy`) are untouched and still available. `iscStrategy` is the recommended default going forward.

### Dependency alias resolution
`run map.X.stage.Y` in ISC source captures the alias name `X`. The converter resolves the alias to the actual system code via the document's `dependencies` list (which maps `aliasName → target`).

## Verification
- ✅ `transliterate("bgnpcgn-ukr-Cyrl-Latn-2019", "Антон")` works via `iscBundledStrategy`
- ✅ All 289 maps load and transliterate via the ISC strategy
- ✅ End-to-end test suite (`test/isc/end-to-end.test.ts`) verifies 7388 test vectors with 99.95% pass rate
- ✅ TypeScript types pass strict mode
