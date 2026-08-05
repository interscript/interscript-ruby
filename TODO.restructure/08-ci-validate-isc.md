# 08 — CI: validate .isc parse in all runtimes

## Priority: P2

## Problem
Need CI checks to verify .isc files parse correctly in both Ruby and TS.

## Design
### Ruby CI
```yaml
- name: ISC specs
  run: rspec spec/interscript/isc/ --options /dev/null

- name: Parse all maps
  run: ruby -Ilib -e '
    require "interscript/isc"
    Dir.glob("../maps/maps/*.isc").each do |path|
      Isc::Parser.parse(File.read(path), filename: File.basename(path))
    end
  '
```

### TS CI
```yaml
- name: ISC parser tests
  run: npx vitest run test/isc/

- name: Parse all maps
  run: npx tsx -e '
    import { parseIsc } from "./src/isc/parser"
    import { readdirSync, readFileSync } from "fs"
    for (const f of readdirSync("../maps/maps").filter(f => f.endsWith(".isc"))) {
      parseIsc(readFileSync(`../maps/maps/${f}`, "utf8"))
    }
  '
```

### Maps repo CI
```yaml
- name: ISC parse check
  run: |
    cd ../interscript-ruby
    ruby -Ilib -e 'require "interscript/isc"; Dir.glob("../maps/maps/*.isc").each { |p| Isc::Parser.parse(File.read(p), filename: File.basename(p)) }'

- name: Codemod drift check (optional)
  run: |
    # Verify .isc files are valid (no manual edits broke the format)
    # This is a lightweight check, not a full codemod re-run
