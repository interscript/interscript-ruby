# 04 — Commit .isc files to the maps repo

## Priority: HIGH

## Current State
- All 289 .isc files generated in `/tmp/isc-verify/` and `/Users/mulgogi/src/interscript/maps/maps/`.
- The maps repo (`interscript/maps`) has 289 untracked .isc files.
- The interscript-ruby repo (`feat/isc-parser-codemod` branch) has the codemod
  and grammar but not the .isc files.

## Steps
1. In the maps repo, create a branch: `feat/isc-maps`.
2. Stage all .isc files: `git add maps/*.isc` (explicit, not `-A`).
3. Verify: `git diff --cached --name-only | grep -c '.isc'` should be 289.
4. Commit with message: `feat: add ISC-format maps for all 289 systems`.
5. Push and open a PR against `interscript/maps`.

## Considerations
- The .isc files are GENERATED from .imp via the codemod. Consider adding a
  CI check that re-runs the codemod and verifies no drift.
- The maps repo may have its own CI (CodeQL, lint). Check before pushing.
- Coordinate with the user before pushing — this is a large change to a
  shared repo.