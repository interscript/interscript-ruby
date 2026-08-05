# 10 — IS 1 specification (Metanorma)

## Priority: P2

## Goal
Compile `spec/isc/document.adoc` and publish to the website.

## Architecture impact
The spec should document:
- ISC as the canonical source format (not .imp or .json)
- Both Ruby and TS parsers as first-class implementations
- YAML round-trip as an optional interchange format
- JsonIR as an optional compiled format

## Steps
1. Update spec/isc/document.adoc to reflect current grammar
2. Add YAML round-trip annex
3. Add TS parser specification
4. Compile with Metanorma
5. Publish to interscript.org/spec
