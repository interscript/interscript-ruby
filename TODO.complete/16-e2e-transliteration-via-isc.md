# 16 — E2E transliteration via .isc spec

## Goal
Add a spec that verifies `Interscript.transliterate()` works end-to-end
with `.isc` files from the maps repo.

## Implementation
Add to `spec/interscript/isc/`:
```ruby
it "transliterates using .isc files from maps repo" do
  Interscript.load_path.unshift("../../maps/maps")
  result = Interscript.transliterate("alalc-amh-Ethi-Latn-1997", "ሀ")
  expect(result).to eq("ha")
end
```

## Status: Already verified manually
```ruby
Interscript.transliterate("alalc-amh-Ethi-Latn-1997", "ሀ")  # => "ha"
```
