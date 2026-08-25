# 09 — Open PRs and merge

## Priority: P0 — blocks all other work

## Steps

### Maps repo PR
```bash
cd interscript/maps
gh pr create --title "feat: replace .imp with .isc format (289 maps)" \
  --body "All 289 maps converted from Ruby DSL to ISC format."
```

### Ruby repo PR
```bash
cd interscript/interscript-ruby
gh pr create --title "feat: ISC format — parser, NodeAdapter, YAML round-trip, serializer" \
  --body "Complete ISC infrastructure: 105 specs, 289/289 parse, NodeAdapter, YAML bridge, serializer."
```

### Merge order
1. Maps repo PR first (provides .isc files)
2. Ruby repo PR second (depends on .isc for locate)
3. Website changes third (depends on both)
