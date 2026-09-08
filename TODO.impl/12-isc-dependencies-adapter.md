# [COMPLETE 2026-09-08 — repro spec RED then GREEN; deps wired, constraint key fixed, library-import semantics restored] 12 — Ruby adapter drops ISC dependencies (P1)

## Goal
`NodeAdapter#build` wires the ISC document's dependencies into the
Node::Document (dependencies, dep_aliases, lazily-loaded documents) so
`run map.<alias>.stage.<name>` works — unblocking PR #769 and the
corpus-era rspec failures.

## Why
Root cause of the 79-failure batch (named 2026-09-08): the adapter
sets metadata/tests/aliases/stages/name and silently drops
`dependencies` — every cross-map run in an `.isc` document then
dereferences nil (`reverse_run` on nil at interpreter.rb:78 via the
run branch). Local runs never saw it: they resolved the installed
`interscript-maps-2.4.3` gem (`.imp`) because the gem's load path
prefers installed map gems over siblings.

## Spec (TDD)

1. RED: a spec that forces the ISC corpus onto the load path
   (`Interscript.load_path` prepended with the maps checkout),
   transliterates `bgnpcgn-ukr-Cyrl-Latn-2019` "Антон Олегович", and
   asserts "Anton Olehovych" — currently raises the nil crash.
2. GREEN: `build` constructs `Node::Dependency` per ISC dependency —
   `full_name`, `name` (the alias, symbolized), `import = false` (ISC
   v1 carries no import marker; alias-having deps are reached through
   `dep_aliases`, which `import` does not gate), `document` parsed
   through the same dispatch the compiler uses (`.isc` → parse_isc,
   else DSL.parse) so chains resolve recursively.
3. `doc.dep_aliases[name] = dep` mirroring the DSL (document.rb:40).

## Acceptance
- The repro spec green; PR #769's gallery parity green against the
  real corpus (not the stale gem).
- Corpus-census rspec run: failure count measured before/after,
  remainder categorized in the PR body (this fix may not cure all 79;
  what remains is named, not hidden).
