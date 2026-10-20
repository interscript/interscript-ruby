# CLAUDE.md — interscript-ruby

The Ruby runtime: ISC transliteration engine + the in-gem neural model
runtime (`Interscript::ML`). Project purpose and direction:
`interscript-models` README.

## Facts that bite

- **Canonical code is origin/main.** Work in fresh clones; never trust
  a stale local tree's version files or gemspec.
- Spec suite: `bundle exec rake`. `SKIP_JS=1 SKIP_PYTHON=1` exclude the
  cross-compiler *execution* specs (they read the monorepo's sibling
  `js/test-compiler/` assets); that coverage is owned by rake.yml's
  push matrix, not by the release gate.
- Release: push `v*` tag → `release.yml` → specs → `rubygems/release-gem@v1`
  (trusted publishing, registered for this repo). The `release` rake
  task is hand-rolled (push the built gem) — bundler's own release task
  aborts when the tag already exists.
- `interscript-maps` is pinned `~> 2.5` (the published lineage), NOT
  derived from the gem version. Do not "fix" this into an auto-formula.
- `Interscript::ML` optional deps (onnxruntime, rubyzip, numo-narray)
  load lazily and raise named `LoadError`s.
- ByT5 byte table: ids are byte + 3 with trailing EOS (id 1). Raw
  `text.bytes` is silent garbage.
- Conformance fixtures come from interscript-models and run env-gated
  (`SECRYST_E2E_ZIP`, `CONFORMANCE_VECTORS`).

## Laws

- PRs only, never commit to main. Versions are owner decisions.
- Gem/package versions, dependency floors, and supported platforms are
  owner decisions — findings are input, not authority to change them.
