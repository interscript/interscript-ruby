# 06 — Ruby DSL STANDARD_ARRAY_KEYS bug

## Priority: P3 (ISC already correct)

## Bug
`lib/interscript/dsl/metadata.rb` line 47-61: methods for
`notes`, `implementation_notes`, `original_notes`, `url` process input
but **never store the result** in `@node`.

```ruby
STANDARD_ARRAY_KEYS.each do |sym|
  define_method sym do |stuff|
    stuff = Array(stuff)
    stuff.map do |i|
      case i
      when String then i
      else
        warn "..."
        i.inspect
      end
    end
    # BUG: result is discarded. Missing: @node[sym] = result
  end
end
```

## Impact
- Ruby DSL `metadata.data[:url]` returns nil for ALL maps
- ISC parser correctly stores these fields
- Deep equivalence checker must skip these fields

## Fix
```ruby
STANDARD_ARRAY_KEYS.each do |sym|
  define_method sym do |stuff|
    @node[sym] = Array(stuff).map do |i|
      case i
      when String then i
      else
        warn "[#{@map_name}] Metadata key #{sym} expects String"
        i.inspect
      end
    end
  end
end
```

## Verification
After fix, remove the skip in `exe/verify_isc_deep`:
```ruby
skip_fields = [:nonstandard, :tests, :stages, :aliases, :dependencies]
# Remove :url, :notes, :implementation_notes, :original_notes from skip
```
Re-run: all 289 maps should match on these fields.
