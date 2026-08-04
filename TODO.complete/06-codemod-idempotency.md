# 06 — Codemod idempotency

## Goal
Verify the codemod is idempotent: running it twice produces the same output.
This ensures the codemod is a clean, deterministic transformation.

## Test
```ruby
# Generate .isc from .imp
isc1 = Codemod.convert(imp_source, filename: "map.imp")
# Run codemod again on the .isc output (treating it as .imp-like input)
isc2 = Codemod.convert(isc1, filename: "map.imp")
# They should be identical
expect(isc1).to eq(isc2)
```

Note: The codemod currently expects .imp input (Ruby DSL syntax).
Running it on .isc output would be a different test. Instead, verify:
1. Serializing a document hash produces valid ISC
2. Parsing that ISC produces the same document hash
3. Serializing again produces the same ISC

This is the ISC → ISC idempotency check (via Serializer + Parser).
