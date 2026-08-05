# 01 — TS ISC Parser (Peggy grammar)

## Priority: P0 — blocks all website restructure work

## Problem
The TS runtime currently consumes compiled JSON IR (`.json` files generated
by Ruby). To eliminate JSON IR, the TS runtime needs its own ISC parser.

## Design

Port the Ruby Parslet grammar to Peggy (PEG parser generator for JS/TS).
The grammar rules map 1:1:

| Parslet (Ruby) | Peggy (JS) |
|----------------|------------|
| `str("system")` | `"system"` |
| `whitespace` | `\\s+` |
| `quoted_string` | `'"' ('\\\\' ./ | !'"' .)* '"'` |
| `braced(inner)` | `'{' \\s* inner \\s* '}'` |
| `rule(:name) do ... end` | `name = ...` |

### Structure
```
interscript-ts/
  src/
    isc/
      grammar.peggy          # Peggy grammar (source of truth for TS)
      parser.ts              # Wrapper: parse(src) → document hash
      document-builder.ts    # Hash → typed CompiledMap
      types.ts               # IscDocument, IscStage, IscRule, IscItem types
  test/
    isc/
      parser.test.ts         # Unit tests
      parity.test.ts         # Cross-validate with Ruby document hashes
```

### Grammar scope (from Ruby Parslet)
- System block: `system "CODE" { body }`
- Metadata: `metadata { key value ... }`
- Tests: `tests { "input" -> "expected" }`
- Aliases: `aliases { name = item }`
- Stages: `stage name { parallel { ... } sub "a" "b" ... }`
- Items: quoted strings, any(), capture(), ref(), none, primitives
- Constraints: before, after, not_before, not_after
- Directives: run, separate, compose, downcase/upcase/title_case

### API
```typescript
import { parseIsc } from "interscript-ts/isc"

const doc = parseIsc(iscSource, "map.isc")
// doc: { systemCode, metadata, tests, stages, aliases, dependencies }
```

### Loader strategy
```typescript
import { iscStrategy } from "interscript-ts"

configure({ strategies: [iscStrategy({ baseUrl: "/maps" })] })
// Fetches /maps/foo.isc, parses, feeds to runtime
```

## Verification
- Parse all 289 .isc files
- Document hash matches Ruby document hash (cross-validate)
- Transliteration output matches Ruby 100%
