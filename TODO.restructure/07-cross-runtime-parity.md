# 07 — Cross-runtime parity testing

## Priority: P1

## Problem
With two ISC parsers (Ruby Parslet + TS Peggy), we need to verify
they produce semantically equivalent document models.

## Design
1. Ruby parses all 289 .isc files → document hashes
2. TS parses all 289 .isc files → document hashes
3. Compare: same system code, same test count, same stage structure
4. Compare: same transliteration output for all test vectors

### Test structure
```
interscript-ts/test/isc/
  cross-parity.test.ts   # Compare TS parse vs Ruby parse
  transliteration.test.ts # Compare TS transliteration vs known-good
```

### Ruby side: export reference hashes
```bash
ruby -Ilib -e '
  require "interscript/isc"
  require "json"
  results = {}
  Dir.glob("../maps/maps/*.isc").each do |path|
    tree = Isc::Parser.parse(File.read(path))
    doc = Isc::DocumentBuilder.build(tree)
    results[doc[:systemCode]] = {
      tests: doc[:tests].size,
      stages: doc[:stages].size,
    }
  end
  File.write("test/fixtures/reference-hashes.json", JSON.pretty_generate(results))
'
```

### TS side: parse and compare
```typescript
describe("cross-runtime parity", () => {
  const refs = JSON.parse(readFileSync("test/fixtures/reference-hashes.json"))
  for (const code of Object.keys(refs)) {
    it(`${code}: matches Ruby parse`, () => {
      const src = readFileSync(`../maps/maps/${code}.isc`, "utf8")
      const doc = parseIsc(src)
      expect(doc.tests.length).toBe(refs[code].tests)
      expect(doc.stages.length).toBe(refs[code].stages)
    })
  }
})
```
