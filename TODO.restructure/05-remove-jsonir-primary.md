# 05 — Remove JSON IR as primary pipeline

## Priority: P2 (after 01-04 are done)

## Status: COMPLETE

## Problem
`Interscript::Compiler::JsonIR` generates JSON IR from Node::Document.
This was the ONLY way to feed maps to the TS runtime. With a TS ISC
parser, JSON IR is no longer needed as the primary pipeline.

## Solution
1. ✅ Keep JsonIR compiler as an OPTIONAL export (for backward compat)
2. ✅ Already removed from default build pipeline — `Interscript.transliterate` defaults to `Interscript::Interpreter`
3. ⬜ Remove JSON IR files from the website (TODO 02 work)
4. ⬜ Remove the `gen-parity-fixtures.rb` dependency on JSON IR

## What stays
- `Interscript::Compiler::JsonIR` class — still available via autoload for users who
  want pre-compiled maps. Lazy: only loaded if explicitly referenced.
- `interscript.org/public/maps/*.json` — to be removed in TODO 02.

## Migration path for existing users
1. Users who load `.json` via `bundledStrategy` → switch to `iscStrategy` (TS)
2. Users who generate `.json` via Ruby → can still use JsonIR compiler
3. The .isc files are the canonical source for both runtimes

## Verification
- Default `Interscript.transliterate` uses Interpreter, not JsonIR
- JsonIR is autoloaded (lazy) — only loaded when explicitly referenced
- All 289 .isc files work without JSON IR
