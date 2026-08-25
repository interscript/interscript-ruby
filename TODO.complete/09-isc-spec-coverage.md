# 09 — ISC spec coverage

## Current: 97 specs, 96 pass

### Missing specs
- YamlBridge unit tests (to_yaml, from_yaml for each item type)
- Serializer unit tests (serialize for each construct)
- Round-trip spec for real maps (blocked on lutaml-model fix)
- Codemod idempotency spec
- NodeAdapter edge case specs (decompose, separate with separator)

### Goal
100% spec coverage for all public methods in:
- Parser
- DocumentBuilder
- NodeAdapter
- YamlBridge
- Serializer
- Codemod
