# 03 — Website: render map pages from .isc at build time

## Priority: P1

## Problem
Map detail pages (e.g., `/maps/bgnpcgn-ukr-Cyrl-Latn-2019`) currently
render from JSON IR metadata. They could render directly from .isc source.

## Solution
At Astro build time:
1. Read each `.isc` file
2. Parse with TS ISC parser (or Ruby if building with Ruby available)
3. Extract metadata, tests, stage structure
4. Render to static HTML

### Pages affected
- `/maps/[code]` — map detail (metadata, rules, tests)
- `/maps` — catalogue (list all maps with metadata)
- `/authorities/[auth]` — authority grouping

### Implementation
```typescript
// astro.config or scripts/generate-map-pages.ts
import { parseIsc } from "interscript-ts/isc"
import { readFileSync } from "fs"

const maps = readFileSync("public/maps/*.isc").map(parseIsc)
// Generate static pages from parsed documents
```

### Benefit
- No JSON IR files needed
- Map pages always reflect the latest .isc source
- No compilation step or drift
