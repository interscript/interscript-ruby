# 02 — IS 1 specification compilation

## Priority: MEDIUM

## Current State
- The IS 1 specification exists as a Metanorma AsciiDoc file at
  `spec/isc/document.adoc`.
- It has not been compiled to HTML/PDF/XML yet.
- The spec describes the ISC format formally but may be out of date with
  recent grammar changes.

## Steps
1. Review `spec/isc/document.adoc` against the current grammar:
   - Verify all grammar rules are documented.
   - Update the metadata, tests, stages, and items sections.
   - Add the escaped-brace syntax (`\{`, `\}`) for raw text blocks.
   - Document the `separate separator` and `decompose` directives.

2. Compile the spec:
   ```bash
   bundle exec metanorma spec/isc/document.adoc
   ```

3. Publish the compiled HTML/PDF to the interscript.org website.

## Annexes to Add
- **Migration Annex**: step-by-step guide for converting .imp → .isc.
- **Grammar Reference**: complete BNF/PEG grammar extracted from the Ruby code.
- **Examples**: real-world ISC snippets from the 289 maps.