# 13 — Open maps PR for .imp → .isc migration

## Status: Ready to open

Branch `feat/imp-to-isc-migration` is pushed to interscript/maps.
All 289 .imp files renamed to .isc with ISC content.
Git history preserved. 289/289 .isc files parse.

## Steps
```bash
cd interscript/maps
gh pr create --title "feat: replace .imp with .isc format (289 maps)" \
  --body-file /tmp/maps-pr-body.txt
```

## Verification (already done)
- 0 .imp files remain
- 289 .isc files exist and parse
- Old .imp history accessible via `git log -- maps/foo.imp`
