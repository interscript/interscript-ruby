# 02 — Fix 3 remaining deep equivalence diffs

## Current: 284/289 equivalent, 3 differ, 2 IMP-fail

### din-san-Deva-Latn-33904-2018
- **Issue**: rule counts imp=155 isc=154 (off by 1)
- **Root cause**: One sub rule inside a parallel block is not being
  captured by the ISC parser. The IMP hash has 114 parallel children;
  the ISC hash has 113. Need to diff the specific rules to find the
  missing one.
- **Fix**: Compare IMP parallel children with ISC parallel rules
  item by item to find the missing rule.

### mvd-bel-Cyrl-Latn-2008
- **Issue**: ISC notes contain Cyrillic comments (`# Инструкция...`)
  that should have been stripped as comments, not included as note text
- **Root cause**: The .imp has a complex notes structure with Cyrillic
  comments followed by `- |` heredoc items. The codemod treats the
  comment block as part of the first heredoc note.
- **Fix**: The codemod's notes handler needs to properly skip
  multi-line comment blocks before the first `- |` item.

### var-ara-Arab-Arab-rababa
- **Issue**: rule counts imp=1 isc=0
- **Root cause**: The .imp has `rababa config: "200"` which the
  codemod converts to a comment. The Ruby DSL counts it as 1 rule.
  ISC intentionally treats rababa as a comment (not a rule).
- **Resolution**: This is BY DESIGN. The deep checker should accept
  this as expected (add to KNOWN_EXPECTED set).
