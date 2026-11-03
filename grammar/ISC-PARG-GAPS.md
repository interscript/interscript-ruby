# ISC .parg port — expressiveness notes and gaps

Status of the port: `grammar/isc.parg` expresses **every rule of the
canonical Ruby-DSL grammar** (`lib/interscript/isc/grammar/concerns/*.rb`
+ `core.rb`, origin/main lineage). No construct of the concerns proved
inexpressible in the parsanol .parg surface. What follows is the precise
record of the four places the port could not be a verbatim transcription
and why, plus the porting traps the corpus caught. Validation evidence:
tools/isc-parg-check parses 319/319 corpus files (318 `maps/` + 1
`maps-staging/`) and rejects 4/4 negative fixtures, with verdict parity
against the Ruby DSL (`Interscript::Isc::Parser.parse_with_dsl`) on every
file, positive and negative.

## 1. Keyword alternation: shadow-lint-forced reorder (deviation, safe)

- Construct: `rule(:keyword)` in `concerns/items.rb` — the ordered
  literal list of reserved words, used ONLY under `.absent?` (negative
  lookahead) in `alias_reference` and `alias_arg`.
- Ruby spelling: `... | str("any") | ... | str("any_character")` —
  `"any"` precedes `"any_character"`.
- Why the port deviates: the parsanol .parg compiler rejects
  prefix-shadowed alternation branches at compile time ("branch 21
  ("any") shadows branch 34 ("any_character")"), because in a plain
  choice the shorter literal would make the longer unreachable.
- Resolution: `"any_character"` moved before `"any"` (longest-first),
  as the lint instructs.
- Why it is safe: `keyword` appears only under `!`. For a negative
  lookahead, every branch ordering is equivalent — the predicate fails
  whenever ANY branch matches at the position, and the two branch sets
  are identical. No corpus input changes verdict under the reorder.

## 2. Dead concern rules: omitted (not a .parg limitation)

- Construct: `authority_field`, `source_spelling_field`,
  `target_spelling_field`, `identifying_field`, `name_field` in
  `concerns/metadata.rb`.
- Why omitted: none of them is reachable from `metadata_field` (they
  are defined but never listed in its alternation). In the Ruby DSL
  they are dead code; an `authority "X"` line parses via
  `generic_field` (identifier + quoted value), same as here.
- Consequence: none for acceptance — a bare `authority "..."` /
  `name "..."` metadata line parses identically through
  `generic_field` on both engines (verified on the corpus, where
  `authority_id`, `name`, `url`, ... all flow through the generic
  branch).

## 3. Unreachable lexical helpers: not carried over

- `space?`, `newlines`, `newlines?` (`concerns/primitives.rb`) and
  `list_item` (`concerns/items.rb`, an alias of `item`) are defined but
  never referenced by a reachable rule. They are folded into their use
  sites here (`wsq`, `list_items`). `braced(inner)` is a Ruby method,
  not a rule; every use site spells the scaffold inline.

## 4. The `field_value` repeat-binding trap (expressed; first port got it wrong)

- Construct: `rule(:field_value)` in `concerns/metadata.rb`:
  `(newline.absent? >> (str("}").absent? >> str("{").absent? >> any)).repeat(1)`.
- Trap: the `.repeat(1)` binds over the WHOLE parenthesized group, so
  `newline.absent?` is re-checked per iteration — the raw value run
  stops AT the newline (`din-hye`: `authority_id din` captures `raw:
  "din"`, not the whole metadata block).
- Port: `field_raw = 1*(!newline !"}" !"{" chr)`. The first draft wrote
  `!newline` outside the repetition; the run then swallowed fields up
  to the next `{` and `din-hye-Armn-Latn-32706-2010.isc` failed. The
  harness caught it; the per-iteration guard matches the Ruby
  semantics.

## 5. Related semantics fixed while porting (recorded for reviewers)

- The DSL's `any` matches ANY character including raw newlines —
  multiline `description { ... }` bodies (raw_text) and quoted strings
  cross line breaks. `chr = %x00-10FFFF` here; newline stops exist
  ONLY where the concerns put an explicit `newline.absent?`
  (`line_comment`, `field_raw`, stages' `comment_item`).
- Escape rulings from the concerns are mirrored: `\uXXXX` exactly 4
  hex; `\U` 4..8 hex (`gki-bel "\U040E"`); a lone `\U` accepted
  (un-mar converter corruption). Acceptance parity holds on all three
  corpus shapes.
- The root rule pins full-input consumption with an explicit `!utf`
  (`isc_source`), so the harness rejects trailing garbage without
  relying on engine EOF behavior.

## Not a gap, but out of harness scope

The harness gates ACCEPTANCE (parse/reject verdicts). The capture-tree
SHAPE produced by a .parg artifact is parg-shaped (`cap` nodes); the
gem's `Isc::Normalizer` owns DSL-tree equivalence for the artifact
runtime. Verifying shape parity byte-for-byte against
`parse_with_dsl` trees is the gem's corpus gate's job, not this
harness's.
