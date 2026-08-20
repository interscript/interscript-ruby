# 04 — Ruby DSL STANDARD_ARRAY_KEYS bug fix

## Priority: LOW (affects Ruby DSL only, ISC already correct)

## Current State
The Ruby DSL's `lib/interscript/dsl/metadata.rb` defines:

```ruby
STANDARD_ARRAY_KEYS = %i[notes implementation_notes original_notes url]

STANDARD_ARRAY_KEYS.each do |sym|
  define_method sym do |stuff|
    stuff = Array(stuff)
    stuff.map do |i|
      case i
      when String
        i
      else
        warn "[#{@map_name}] Metadata key #{sym} expects all Array elements to be String"
        i.inspect
      end
    end
    # BUG: the processed array is never stored in @node!
  end
end
```

The method processes `stuff` but **never assigns the result to `@node[sym]`**.
This means `notes`, `implementation_notes`, `original_notes`, and `url` are
parsed from `.imp` files but silently discarded by the Ruby DSL.

## Impact
- Deep equivalence checker shows `imp=nil` for these fields across ALL maps.
- The ISC parser correctly stores them — ISC is strictly more capable.
- Users relying on Ruby DSL `metadata.data[:url]` get `nil`.

## Fix
```ruby
STANDARD_ARRAY_KEYS.each do |sym|
  define_method sym do |stuff|
    @node[sym] = Array(stuff).map do |i|
      case i
      when String then i
      else
        warn "[#{@map_name}] Metadata key #{sym} expects String, got #{i.class}"
        i.inspect
      end
    end
  end
end
```

## Verification
After fix, re-run `exe/verify_isc_deep` — the metadata comparison for
`url`, `notes`, `implementation_notes`, and `original_notes` should pass
for all 289 maps.