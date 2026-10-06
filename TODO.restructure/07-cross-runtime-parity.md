# 07 — Cross-runtime parity testing

## Priority: P1

## Status: COMPLETE

## Problem
With two ISC parsers (Ruby Parslet + TS recursive descent), we need to verify
they produce semantically equivalent document models.

## Implementation

Two-layer parity check:

### 1. Structural parity (parser output shape)
- Ruby parses all 289 .isc files, emits per-file summary: `[code, testCount, stageCount, aliasCount, depCount]`
- TS parses same files, emits same summary shape
- `diff` of the two summaries shows the only discrepancy: Ruby produces phantom `{input: "", expected: ""}` test entries for empty `tests { # comment }` blocks (8 files). TS correctly produces 0 tests for these.

### 2. Behavioral parity (transliteration output)
- TS loads all 289 .isc files via `iscBundledStrategy`
- For each test vector, run TS transliteration and compare to expected
- Result: **99.95% pass rate (7384/7388 test vectors)**

### Test fixtures
- `interscript-ts/test/isc/end-to-end.test.ts` — runs the full parity check
- Skips maps whose dependencies transitively touch libraries not yet migrated to .isc (`unicode`, `posix`, `var-Cyrl`, `var-kor`, and any dep not in sources)

### Ruby side: export reference hashes
```bash
ruby -Ilib -e '
  require "interscript/isc"
  Dir.glob("../maps/maps/*.isc").sort.each do |path|
    fname = File.basename(path, ".isc")
    src = File.read(path)
    tree = Interscript::Isc::Parser.parse(src, filename: fname + ".isc")
    doc = Interscript::Isc::DocumentBuilder.build(tree, filename: fname + ".isc")
    puts [fname, doc[:tests].size, doc[:stages].size, doc[:aliases].size, doc[:dependencies].size].join(",")
  end
'
```

## Known discrepancies (4 tests, all explained)

| Map | Issue | Root cause |
|-----|-------|------------|
| `mofa-jpn-Hrkt-Latn-1989` (3 tests) | TS produces "SENO", expected "SENOO" | Rule has `not_after any(space+line_end)`. Ruby's NodeAdapter miscompiles this to empty string, making the rule never match (which happens to match the test expectation). TS compiles it correctly, so the rule applies and drops the long-vowel marker. |
| `var-ara-Arab-Arab-rababa` (1 test) | TS returns input unchanged | This map calls an external ML rababa service for Arabic diacritization. Not applicable to local transliteration. |
