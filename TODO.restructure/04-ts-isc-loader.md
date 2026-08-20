# 04 — TS runtime: ISC loader strategy

## Priority: P1

## Problem
The TS runtime has load strategies for JSON IR (`bundledStrategy`,
`httpStrategy`). Need a new strategy that loads `.isc` source files
and parses them on the fly.

## Design
```typescript
// src/isc/isc-loader.ts
import { parseIsc } from "./parser"
import { normaliseMap } from "../types"

export function iscStrategy(opts: { baseUrl: string }): LoadStrategy {
  return {
    async load(code: string): Promise<CompiledMap | null> {
      const res = await fetch(`${opts.baseUrl}/${code}.isc`)
      if (!res.ok) return null
      const source = await res.text()
      const doc = parseIsc(source, code)
      return normaliseMap(doc) // Convert to CompiledMap shape
    }
  }
}
```

### Backward compatibility
Keep existing JSON IR strategies as optional. Users who prefer
pre-compiled JSON can still use `bundledStrategy` or `httpStrategy`.
The new `iscStrategy` is the recommended default.

## Verification
- `transliterate("bgnpcgn-ukr-Cyrl-Latn-2019", "Антон")` works with iscStrategy
- All 289 maps load and transliterate correctly
- Performance: parse time < 100ms for 95% of maps (large CJK maps may be slower)
