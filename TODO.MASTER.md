# ISC Migration — Master TODO Index

## Status: 247/289 deep equivalent, 289/289 parseable, 100% transliteration parity

This index tracks ALL remaining work across the interscript ecosystem.
Each item links to its detailed TODO in the respective repo.

---

## P0 — Blocks adoption

### [ISC Runtime Integration](rababa/00-isc-runtime-integration.md) ✅ DONE
`NodeAdapter` bridges ISC document hash → `Interscript::Node::Document`.
ISC files can now be used for actual transliteration.

### [Commit .isc files to maps repo](rababa/01-commit-isc-to-maps-repo.md)
289 .isc files generated but not committed to `interscript/maps`.

### [E2E Tests for Website](https://github.com/interscript/interscript.org/blob/astro-migration/TODO.complete/01-e2e-tests.md) ✅ DONE
27/27 Playwright tests passing. Full-map validation: 37/37.

---

## P1 — Ecosystem health

### [Fix Deep Equivalence Diffs](rababa/02-fix-deep-equivalence-diffs.md)
247/289 equivalent. 40 remain (codemod edge cases + description whitespace).
Transliteration output is 100% identical — differences are metadata-only.

### [Fix ISC Spec Failures](rababa/03-fix-isc-specs.md)
73 specs written, ~50 pass. Remaining are syntax issues (system wrappers).

### [TS ISC Parser](https://github.com/interscript/interscript-ts/blob/main/TODO.complete/01-isc-parser-typescript.md)
Port ISC grammar to Peggy for direct .isc loading in browser/Node.

### [Full Parity Fixtures](https://github.com/interscript/interscript-ts/blob/main/TODO.complete/02-generate-full-parity.md)
Commit full-parity.json (7502 samples, 0 diffs) to the TS repo.

---

## P2 — Quality

### [IS 1 Specification](rababa/04-is1-specification.md)
Compile Metanorma document, publish to website.

### [Performance: Large CJK Maps](rababa/05-performance-cjk-maps.md)
6 maps take 15-38s to parse (Parslet backtracking).

### [Ruby DSL Array Keys Bug](rababa/06-ruby-dsl-array-keys-bug.md) ✅ DONE
Fixed: `STANDARD_ARRAY_KEYS` now stores results in `@node`.

---

## Architecture Notes

### Pipeline
```
.isc → Isc::Parser → DocumentBuilder → NodeAdapter → Node::Document → Interpreter
.imp → DSL.parse → Node::Document → Interpreter
                    ↓
              JsonIR Compiler → .json → interscript-ts → browser
```

### ISC is now a first-class source format
With the NodeAdapter, .isc files can:
- Be parsed (Parser)
- Be built into documents (DocumentBuilder)
- Be converted to Node objects (NodeAdapter)
- Be used for transliteration (Interpreter)
- Be compiled to JSON IR (JsonIR Compiler)

### What's left for true parity
1. Commit .isc to maps repo (mechanical)
2. Update `Interscript::Path` to resolve `.isc` extension
3. Port ISC parser to TypeScript (for browser-native .isc loading)
4. Fix remaining 40 metadata edge cases (cosmetic)
