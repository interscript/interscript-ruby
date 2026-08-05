# 05 — Remove JSON IR as primary pipeline

## Priority: P2 (after 01-04 are done)

## Problem
`Interscript::Compiler::JsonIR` generates JSON IR from Node::Document.
This was the ONLY way to feed maps to the TS runtime. With a TS ISC
parser, JSON IR is no longer needed as the primary pipeline.

## Solution
1. Keep JsonIR compiler as an OPTIONAL export (for backward compat)
2. Remove it from the default build pipeline
3. Remove JSON IR files from the website
4. Remove the `gen-parity-fixtures.rb` dependency on JSON IR

## What stays
- `Interscript::Compiler::JsonIR` class — still available for users who
  want pre-compiled maps
- `interscript.org/public/maps/*.json` — removed (replaced by .isc)

## Migration path for existing users
1. Users who load `.json` via `bundledStrategy` → switch to `iscStrategy`
2. Users who generate `.json` via Ruby → can still use JsonIR compiler
3. The .isc files are the canonical source for both runtimes
