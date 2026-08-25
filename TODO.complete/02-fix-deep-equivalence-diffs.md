# 02 — Fix remaining 13 deep equivalence differences

## Priority: P1

## Current State
- 274/289 deep equivalent
- 2 IMP-fail (bgnpcgn-tuk: Ruby DSL can't parse, ISC can)
- 13 differ (cosmetic / edge cases)

## Categories

### A. Description whitespace (5 maps) — `normalize_heredoc`
**Maps:** alalc-kor, gki-bel, var-pra, var-san + 1

The `normalize_heredoc` method strips ALL leading whitespace per line. The
Ruby DSL's YAML heredoc strips only the COMMON indent (dedent), preserving
relative indentation.

**Fix:** Replace the simple strip with a proper dedent algorithm:
1. Find minimum indent across non-blank lines
2. Strip that amount from every line
3. Handle the first line specially (grammar consumed its leading whitespace
   after the opening `{`)

**Risk:** Changing normalize_heredoc regressed 91 maps last time (270→179).
The new algorithm must be strictly better than the current simple strip.

### B. Codemod edge cases (6 maps)
**Maps:** alalc-tir x2, bgnpcgn-fas, mext-jpn, odni-ara/fas/prs

Each has a unique metadata pattern the codemod mishandles:
- `alalc-tir`: description followed by `implementation_notes: |` heredoc
- `bgnpcgn-fas`: `TODO: Add tests` treated as metadata field
- `mext-jpn`: CJK name field, description mismatch
- `odni-*`: `notes: - item` or `[]` leaking into description

**Fix:** Audit each .imp individually, extend codemod handlers.

### C. Rule count (2 maps)
- `din-san-Deva-Latn-33904-2018`: imp=155 isc=154 (off by 1, likely `run` or `deep`)
- `var-ara-Arab-Arab-rababa`: imp=1 isc=0 (rababa directive → comment, expected)

**Fix for din-san:** Diff the stage body item-by-item between .imp and .isc.
