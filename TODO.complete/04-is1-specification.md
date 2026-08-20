# 04 — IS 1 specification compilation and publication

## Priority: P2

## Current State
- `spec/isc/document.adoc` exists but hasn't been compiled
- The spec describes ISC format but may lag behind grammar changes
- No published HTML/PDF

## Steps

### 1. Review spec against grammar
- Verify all grammar rules documented
- Add escaped-brace syntax (`\{`, `\}`) for raw text
- Document `separate separator`, `decompose` directives
- Add `any(space+line_end)` pattern

### 2. Compile
```bash
bundle exec metanorma spec/isc/document.adoc
```
Produces HTML, PDF, and XML.

### 3. Publish
- Copy compiled HTML to `interscript.org/public/spec/`
- Add a `/spec` page on the website linking to it
- Version the spec (IS 1.0) and track changes

## Spec Structure (reference: ISO 24229)
1. Scope
2. Normative references
3. Terms and definitions
4. System codes
5. Metadata block
6. Tests block
7. Aliases block
8. Stages (parallel, sequence, sub, run, separate, compose)
9. Items (strings, primitives, constructors, functions)
10. Constraints (before, after, not_before, not_after)
11. Annex A: Migration from .imp (codemod)
12. Annex B: Grammar reference (PEG)
13. Annex C: Examples
