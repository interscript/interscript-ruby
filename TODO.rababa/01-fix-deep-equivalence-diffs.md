# 01 — Fix remaining 13 deep equivalence differences

## Priority: HIGH

## Current State
- 274/289 deep equivalent
- 2 IMP-fail (ISC parses, Ruby DSL can't — ISC is strictly more capable)
- 13 differ (cosmetic / edge cases)

## Remaining Differences

### Description whitespace normalization (5 maps)
- `alalc-kor-Hang-Latn-1997`: description quoted value spans multiple lines
- `gki-bel-Cyrl-Latn-2000`: description has relative indentation preserved by DSL
- `var-pra-Deva-Latn-iast-1912`, `var-san-Deva-Latn-iast-1912`: description content truncation

**Fix:** The `normalize_heredoc` in `DocumentBuilder` strips ALL leading whitespace.
The DSL strips only the COMMON indent (YAML dedent). Need a proper dedent
algorithm that:
1. Finds the minimum indent across all non-blank lines
2. Strips only that amount, preserving relative indentation
3. Handles the first line specially (grammar consumed its indent after `{`)

### Codemod edge cases (6 maps)
- `alalc-tir-Ethi-Latn-1997/2011`: description includes `implementation_notes:` text
- `bgnpcgn-fas-Arab-Latn-1956`: `TODO: Add tests from PDF` treated as metadata field
- `mext-jpn-Hrkt-Latn-1954`: metadata name has CJK text, description mismatch
- `odni-ara/fas/prs-Arab-Latn-2004`: description `[]` or `notes:` text leaking

**Fix:** Audit each .imp file's metadata block structure and extend the codemod
to handle the specific patterns. Most are multi-line description values where
the codemod's handler chain misidentifies the field boundaries.

### Rule count (2 maps)
- `din-san-Deva-Latn-33904-2018`: imp=155 isc=154 (off by 1)
- `var-ara-Arab-Arab-rababa`: imp=1 isc=0 (rababa directive — expected, not a bug)

**Fix for din-san:** Compare the stage body item-by-item between .imp and .isc
to find the missing rule. Likely a `run` or `deep`/`compose` directive not counted.
