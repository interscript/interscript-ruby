# 03 — Commit .isc files to maps repo

## Status: Blocked on user confirmation

289 .isc files are generated in `/tmp/isc-verify/` but not committed
to the `interscript/maps` repo.

## Steps
1. Generate .isc into the maps repo:
   ```bash
   ruby -Ilib exe/codemod-imp-to-isc --out-dir=../maps/maps ../maps/maps/*.imp
   ```
2. In the maps repo, create a branch and stage:
   ```bash
   cd ../maps
   git checkout -b feat/isc-maps
   git add maps/*.isc
   git diff --cached --name-only | grep -c '.isc'  # should be 289
   ```
3. Commit and push (ask user first — shared repo).

## CI Guard
Add a CI check that regenerates .isc from .imp and verifies no drift.
