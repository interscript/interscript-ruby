# 01 — Commit .isc files to the maps repo

## Priority: P0 (canonical source)

## Problem
All 289 `.isc` files are generated in `/tmp/isc-verify/` but not committed
to the `interscript/maps` repo. The maps repo only has `.imp` files.

## Solution

### Steps
1. Generate .isc files into the maps repo:
```bash
cd interscript-ruby
ruby -Ilib exe/codemod-imp-to-isc --out-dir=../maps/maps ../maps/maps/*.imp
```

2. In the maps repo:
```bash
cd ../maps
git checkout -b feat/isc-maps
git add maps/*.isc
git diff --cached --name-only | grep -c '.isc'  # should be 289
git commit -m "feat: add ISC-format maps for all 289 systems"
git push -u origin feat/isc-maps
gh pr create --title "feat: add ISC maps (289 systems)" --body-file ...
```

### CI Guard
Add a CI check that regenerates .isc from .imp and verifies no drift:
```yaml
# .github/workflows/isc-consistency.yml
- name: Regenerate ISC
  run: cd ../interscript-ruby && ruby -Ilib exe/codemod-imp-to-isc --out-dir=../maps/maps ../maps/maps/*.imp
- name: Check for drift
  run: cd ../maps && git diff --exit-code maps/*.isc
```

## Coordination
- Ask user before pushing to `interscript/maps` (shared repo).
- The maps repo has its own CI (CodeQL).
