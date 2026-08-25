# 05 — Performance: optimize Parslet parsing for large CJK maps

## Priority: P2

## Current State
6 maps take 15-38s to parse:

| Map | Lines | Time |
|-----|-------|------|
| var-kor-Kore-Hang-2013 | 30k | 38s |
| lshk-yue-Hani-Latn-jyutping-1993 | 20k | 29s |
| hk-yue-Hani-Latn-1888 | 20k | 23s |
| acadsin-zho-Hani-Latn-2002 | 15k | 23s |
| var-zho-Hani-Latn-wd-1979 | 43k | 20s |
| sac-zho-Hans-Latn-1979 | 26k | 15s |

## Root Cause
Parslet PEG parser has O(n²) backtracking. The `alias_arg` rule's
`zero_width_primitive.absent?` lookahead fires for every `any()` call.
With 5000+ any() calls in var-zho, overhead compounds.

## Optimization Options

### A. Pre-compile .isc → .rb (eliminates runtime parsing entirely)
Compile .isc to a .rb file that constructs Interscript::Node objects:
```ruby
# Generated from var-zho-Hani-Latn-wd-1979.isc
doc = Interscript::Node::Document.new
doc.stages[:main] = Interscript::Node::Stage.new
doc.stages[:main].children << Interscript::Node::Group::Parallel.new(...)
# ... 27,000+ rules
```
Load time: <1s (require vs 20s parse).

### B. Switch parser engine
- **Racc** (LALR): no backtracking, O(n)
- **Tree-sitter**: C-speed, incremental parsing
- **Hand-written recursive descent**: fastest, most maintenance

### C. Memoize lookaheads
Cache `keyword.absent?` and `zero_width_primitive.absent?` results per
position. Requires Parslet monkey-patch or wrapper atom.

## Recommendation
**Option A** is the right long-term solution:
1. .isc is the human-editable source format
2. .rb (or .json IR) is the runtime-loaded artifact
3. `rake compile` generates artifacts from sources
4. No runtime parsing needed

This aligns with the existing JsonIR compilation pipeline.
