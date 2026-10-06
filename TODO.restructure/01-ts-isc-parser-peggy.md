# 01 — TS ISC Parser

## Priority: P0 — blocks all website restructure work

## Status: COMPLETE

## Problem
The TS runtime consumed compiled JSON IR (`.json` files generated
by Ruby). To eliminate JSON IR, the TS runtime needs its own ISC parser.

## Implementation

Hand-written recursive descent parser in TypeScript. No grammar
generator (Peggy was considered but rejected — hand-written keeps the
dependency surface smaller and gives precise control over position
tracking for error messages).

### Structure
```
interscript-ts/
  src/
    isc/
      types.ts        # IscDocument, IscStage, IscRule, IscItem types
      parser.ts       # parseIsc(source, filename) → IscDocument
      converter.ts    # iscToCompiledMap(doc) → CompiledMapJson
      loader.ts       # iscStrategy, iscBundledStrategy
      index.ts        # public API exports
  test/
    isc/
      parser.test.ts       # 58 unit tests
      end-to-end.test.ts   # 7388 vector parity check
```

### Grammar coverage
- System block: `system "CODE" { body }`
- Metadata: generic fields, description blocks (with `\{`/`\}` escapes), notes blocks (note-list and raw-text forms)
- Tests: `->` syntax with optional `note`, double- and single-quoted strings
- Aliases: `name = item` with all item kinds
- Stages: `parallel`, `sequence`, bare `sub`, `run map.X.stage.Y`, `run stage.X`, `separate`, `compose`, `decompose`, `upcase`/`downcase`/`title_case`
- Items: strings (with escape sequences and `\uXXXX`), `any(...)`, `capture(...)`, `ref(N)`, `none`, primitives, `maybe(...)`, `some(...)`, concat (`+` and juxtaposition)
- Constraints: `before`, `after`, `not_before`, `not_after`

### Leniency for parity
Ruby's Parslet parser silently drops stray tokens in stage/parallel bodies (e.g. the lone `s` in `odni-prs-Arab-Latn-2004.isc`). The TS parser replicates this behavior — unrecognized keywords in stage bodies skip to end-of-line.

### API
```typescript
import { parseIsc } from "interscript-ts/isc"

const doc = parseIsc(iscSource, "map.isc")
// doc: { systemCode, metadata, tests, stages, aliases, dependencies }
```

### Loader strategy
```typescript
import { iscStrategy } from "interscript-ts/isc"

configure({ strategies: [iscStrategy({ baseUrl: "/maps" })] })
// Fetches /maps/foo.isc, parses, feeds to runtime
```

## Verification
- ✅ Parse all 289 .isc files
- ✅ Cross-runtime parity: structural shape matches Ruby (same test counts, stage structure, alias counts)
- ✅ Transliteration parity: 99.95% of test vectors pass (7384/7388)
- ✅ The 4 remaining failures are known edge cases (mofa-jpn's `not_after any(space+line_end)` which Ruby miscompiles to empty, and var-ara-rababa which is an external ML service)
