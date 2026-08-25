# 05 — Performance optimization for large CJK maps

## Priority: MEDIUM

## Current State
6 maps take 15-38 seconds to parse due to Parslet PEG backtracking:

| Map | Lines | Parse Time |
|-----|-------|------------|
| var-kor-Kore-Hang-2013 | ~30k | 38.4s |
| lshk-yue-Hani-Latn-jyutping-1993 | ~20k | 29.4s |
| hk-yue-Hani-Latn-1888 | ~20k | 23.2s |
| acadsin-zho-Hani-Latn-2002 | ~15k | 22.7s |
| var-zho-Hani-Latn-wd-1979 | ~43k | 19.7s |
| sac-zho-Hans-Latn-1979 | ~26k | 15.1s |

## Root Cause
The `alias_arg` rule adds `zero_width_primitive.absent?` lookahead, which is
evaluated for every `any()` call. With 5000+ `any()` calls in var-zho, the
overhead compounds.

## Optimization Options

### Option A: Memoize keyword/primitive lookaheads (quick win)
Cache the result of `keyword.absent?` and `zero_width_primitive.absent?` per
position. Parslet doesn't support this natively, but a wrapper atom could.

### Option B: Switch to a faster parser (medium effort)
Replace Parslet with:
- **Tree-sitter**: Compile a grammar for ISC, get C-speed parsing.
- **Racc (yacc)**: Generate an LALR parser — no backtracking.
- **Hand-written recursive descent**: Fastest but most maintenance.

### Option C: Pre-compile .isc to Ruby AST (long-term)
Instead of parsing .isc at runtime, compile it to a Ruby file at build time.
The compiled file constructs `Interscript::Node` objects directly.

## Recommendation
Option A for immediate relief (target: <5s per file).
Option C for the long term — ISC becomes a source format, compiled to Ruby
or JS at distribution time.