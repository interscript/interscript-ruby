# 05 — ISC integration with existing Interscript runtime

## Priority: HIGH

## Current State
- The ISC parser produces a document hash (metadata, tests, stages, aliases).
- The existing Interscript runtime uses `Interscript::Node::*` objects.
- There is NO bridge between ISC document hash and Interscript::Node objects.
- Users cannot call `Interscript.transliterate("foo.isc", "hello")` yet.

## Required Bridge
Add a method to convert ISC document hash → `Interscript::Node::Document`:

```ruby
class Interscript::Isc::NodeAdapter
  def self.to_interscript_node(isc_doc)
    Interscript::Node::Document.new.tap do |doc|
      doc.metadata = build_metadata(isc_doc[:metadata])
      doc.tests = build_tests(isc_doc[:tests])
      doc.stages = build_stages(isc_doc[:stages])
      doc.aliases = build_aliases(isc_doc[:aliases])
    end
  end
end
```

Then update `Interscript.load_map` to detect `.isc` extension and route
through the ISC parser + adapter instead of the Ruby DSL.

## Files to Create/Modify
- `lib/interscript/isc/node_adapter.rb` (new)
- `lib/interscript.rb` — update `load_map` to support `.isc`
- `lib/interscript/path.rb` — resolve `.isc` files in the maps path

## Verification
```ruby
# Should work identically:
Interscript.transliterate("alalc-amh-Ethi-Latn-1997", "ሀለሐ")  # .imp
Interscript.transliterate("alalc-amh-Ethi-Latn-1997.isc", "ሀለሐ")  # .isc
```

Both should produce the same output.