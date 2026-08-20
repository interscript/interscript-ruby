# 15 — Remove .imp fallback from locate

## Problem
`Interscript.locate` still searches `.imp` as a last-resort fallback.
Since the maps repo no longer has `.imp` files, this is dead code.

## Current code
```ruby
["isc", "iml", "imp"].each do |ext|
```

## Fix
Keep `.imp` in the list for backward compatibility with users who
still have old `.imp` files locally. It doesn't hurt — `.isc` is
checked first.

## Decision: Keep as-is
The `.imp` fallback is harmless and provides backward compatibility.
No code change needed.
