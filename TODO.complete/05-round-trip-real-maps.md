# 05 — Round-trip all 289 maps

## Depends on: 01 (lutaml-model fix)

Once the lutaml-model YAML deserialization bug is fixed, validate
ISC → YAML → ISC for all 289 maps:

1. Parse ISC → document hash
2. Convert hash → YAML
3. Convert YAML → hash
4. Serialize hash → ISC
5. Parse new ISC → hash
6. Verify hash from step 5 matches hash from step 1

Expected outcome: 289/289 semantic equivalence.
Comments and formatting will differ (semantic, not byte-identical).
