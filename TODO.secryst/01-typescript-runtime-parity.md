# 01 — TypeScript runtime parity

## Priority: HIGH

## Current State
- ISC parser exists only in Ruby (Parslet-based).
- The user explicitly requires: "Both Ruby and TS must be first class."
- The TS runtime has no ISC parser — it still uses the old .imp format.

## Scope
1. Port the ISC grammar to TypeScript using a PEG parser library:
   - ** Peggy.js** (formerly peggy) — mature PEG parser generator for JS/TS
   - **tree-sitter-grammar** — if going the C-speed route
   - **Hand-written parser** — following the Ruby grammar's structure

2. Port the DocumentBuilder equivalent (tree → typed object model).
3. Port the codemod (`.imp` → `.isc`) — likely in TS or as a Ruby-generated tool.
4. Ensure the TS runtime can LOAD `.isc` files and produce the same
   transliteration output as Ruby.

## Architecture
```
packages/
  isc-parser/          # TS ISC parser (Peggy grammar)
  isc-document-builder/ # tree → typed model
  isc-codemod/         # .imp → .isc converter
```

## Verification
- Cross-validate: Ruby and TS parsers produce identical document hashes for
  all 289 maps.
- Integration test: run transliteration on test cases, compare Ruby vs TS
  output character-by-character.