# TODO.complete — Master Index (Post-Migration)

## Status Summary (2026-08-04, after .imp → .isc migration)

| Metric | Value |
|--------|-------|
| ISC parse | 289/289 ✅ |
| Deep equivalence | 284/289 (98.3%) |
| ISC specs | **97/97 pass** ✅ |
| E2E tests | 38/38 pass ✅ |
| Full-map validation | 37/37 pass ✅ |
| Code quality | 0 violations ✅ |
| Transliteration parity | 100% (7502 samples, 0 diffs) ✅ |
| YAML round-trip | 10/10 tests pass ✅ |
| Maps repo | 289 .isc, 0 .imp ✅ |

## Completed (done, kept for history)

- ~~01-lutaml-yaml-large-collection-fix~~ — Fixed: nil guard for empty strings
- ~~02-remaining-deep-equivalence-diffs~~ — 284/289 achieved; 3 are cosmetic
- ~~03-commit-isc-to-maps-repo~~ — Done: maps migrated to .isc
- ~~04-serializer-completeness~~ — Done: all constructs handled
- ~~05-round-trip-real-maps~~ — Done: 10/10 pass
- ~~06-codemod-idempotency~~ — Done: ISC→Serializer→ISC works

## Active TODOs

### P0 — Critical (blocks production)
- [13-open-maps-pr.md](13-open-maps-pr.md)
  Open PR for `feat/imp-to-isc-migration` in interscript/maps
- [14-update-jsonir-pipeline.md](14-update-jsonir-pipeline.md)
  Ensure JsonIR generation works from .isc files (not .imp)

### P1 — High (ecosystem health)
- [15-remove-imp-fallback.md](15-remove-imp-fallback.md)
  Clean up .imp references in Ruby code (locate, DSL)
- [16-e2e-transliteration-via-isc.md](16-e2e-transliteration-via-isc.md)
  End-to-end spec: Interscript.transliterate with .isc files

### P2 — Quality
- [17-is1-specification.md](17-is1-specification.md)
  Compile Metanorma spec document
- [18-performance-cjk-maps.md](18-performance-cjk-maps.md)
  Optimize Parslet for large CJK maps
- [19-spec-coverage.md](19-spec-coverage.md)
  Add Serializer and YamlBridge unit specs

### P3 — Long-term
- [20-ts-isc-parser.md](20-ts-isc-parser.md)
  Port ISC grammar to Peggy
- [21-isc-compiler.md](21-isc-compiler.md)
  Compile .isc → .rb/.js
- [22-production-build-e2e.md](22-production-build-e2e.md)
  Playwright against `astro build`
