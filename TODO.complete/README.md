# TODO.complete — Master Index

## Status Summary (2026-08-04)

| Metric | Value |
|--------|-------|
| ISC parse | 289/289 |
| Deep equivalence | 284/289 (98.3%) |
| ISC specs | 96/97 pass |
| E2E tests | 38/38 pass |
| Full-map validation | 37/37 pass |
| Code quality | 0 violations |
| Transliteration parity | 100% (7502 samples, 0 diffs) |

## Active TODOs (by priority)

### P0 — Critical
- [01-lutaml-yaml-large-collection-fix.md](01-lutaml-yaml-large-collection-fix.md)
  Fix lutaml-model YAML deserialization for >100 items per collection
- [02-remaining-deep-equivalence-diffs.md](02-remaining-deep-equivalence-diffs.md)
  Fix 3 remaining metadata edge cases (din-san, mvd-bel, var-ara)
- [03-commit-isc-to-maps-repo.md](03-commit-isc-to-maps-repo.md)
  Push 289 .isc files to interscript/maps repo

### P1 — High
- [04-serializer-completeness.md](04-serializer-completeness.md)
  Add block-form rules, separate directive, Range/Maybe/Some serialization
- [05-round-trip-real-maps.md](05-round-trip-real-maps.md)
  Validate ISC → YAML → ISC for all 289 maps
- [06-codemod-idempotency.md](06-codemod-idempotency.md)
  Verify codemod is idempotent: .imp → .isc → .isc (no drift)

### P2 — Quality
- [07-is1-specification.md](07-is1-specification.md)
  Compile Metanorma spec document and publish
- [08-performance-cjk-maps.md](08-performance-cjk-maps.md)
  Optimize Parslet parsing for 40k+ line CJK maps
- [09-isc-spec-coverage.md](09-isc-spec-coverage.md)
  Add specs for YamlBridge, Serializer, and edge cases

### P3 — Long-term
- [10-ts-isc-parser.md](10-ts-isc-parser.md)
  Port ISC grammar to Peggy for TypeScript runtime
- [11-isc-compiler.md](11-isc-isc-compiler.md)
  Compile .isc → .rb/.js for zero-parse runtime
- [12-production-build-e2e.md](12-production-build-e2e.md)
  Playwright tests against `astro build` output
