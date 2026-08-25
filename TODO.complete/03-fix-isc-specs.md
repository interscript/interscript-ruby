# 03 — Fix ISC spec failures (bundler workaround)

## Priority: P1

## Current State
- 73 ISC specs written, 50 pass, 23 fail
- Failures are syntax issues, not logic errors:
  - Metadata specs need system block wrapper
  - Transform specs need real parser output

## Remaining Failures

### Metadata specs (10 failing)
The grammar requires a root `system "..." { ... }` block. Metadata specs
test `metadata { ... }` standalone, which fails.

**Fix:** Wrap each metadata test:
```ruby
it "parses minimal metadata" do
  tree = parser.parse(<<~ISC, filename: "t.isc")
    system "TEST:eng-Latn:Latn:2026" {
      metadata {
        authority_id test
      }
      stage main { }
    }
  ISC
  expect(tree[:system][:body]).to be_an(Array)
end
```

### Transform specs (8 failing)
Specs construct Parslet trees manually (`{ string: { simple: "x" } }`),
but the actual parser output shape differs (e.g., `Parslet::Slice` instead
of plain strings).

**Fix:** Use real parser output:
```ruby
it "transforms a quoted string" do
  src = %Q{system "X:e-Latn:Latn:1" { stage main { sub "x" "y" } }}
  tree = parser.parse(src, filename: "t.isc")
  doc = Interscript::Isc::DocumentBuilder.build(tree, filename: "t.isc")
  rule = doc[:stages].first[:body].first
  expect(rule[:from]).to be_a(Interscript::Isc::Items::StringValue)
end
```

### Other (5 failing)
- DocumentBuilder tests expecting `:tests` output shape
- Codemod modifier kwargs test
- Concatenation tests

## Infrastructure Fix
The project's `spec/spec_helper.rb` requires `bundler/setup` which fails on
Ruby 3.4.8 (`DidYouMean::SPELL_CHECKERS` NameError).

**Fix:** Update bundler or add a Ruby version guard. The ISC specs use their
own `spec/interscript/isc/spec_helper.rb` that avoids bundler.

## CI Integration
Add to `.github/workflows/ci.yml`:
```yaml
- name: ISC specs
  run: bundle exec rspec spec/interscript/isc/ --options /dev/null
```
