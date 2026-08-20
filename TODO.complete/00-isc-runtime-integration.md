# 00 — ISC runtime integration: bridge ISC document → Interscript::Node

## Priority: P0 (blocks .isc adoption)

## Problem
The ISC parser produces a document hash (`{metadata:, tests:, stages:, aliases:}`),
but the existing `Interscript.transliterate()` only accepts:
1. `.imp` files (parsed via Ruby DSL `instance_exec`)
2. System codes resolved through `Interscript::Path`

There is **no bridge** from ISC document hash to `Interscript::Node::Document`.
Until this exists, `.isc` files cannot be used for actual transliteration.

## Solution

### 1. Create `Interscript::Isc::NodeAdapter`
```
lib/interscript/isc/node_adapter.rb
```
```ruby
module Interscript::Isc
  class NodeAdapter
    def self.to_interscript_node(isc_doc)
      Interscript::Node::Document.new.tap do |doc|
        doc.metadata = build_metadata(isc_doc[:metadata])
        doc.tests = build_tests(isc_doc[:tests])
        isc_doc[:stages].each { |s| doc.stages[s[:name]] = build_stage(s) }
        isc_doc[:aliases].each { |a| doc.aliases[a[:name]] = build_alias(a) }
      end
    end
  end
end
```

### 2. Update `Interscript::Path` to resolve `.isc` files
```ruby
# In Interscript::Path.find_map
[".isc", ".imp"].each do |ext|
  path = "#{dir}/#{name}#{ext}"
  return path if File.exist?(path)
end
```

### 3. Update `Interscript.load_map` to dispatch by extension
```ruby
def self.parse_map(path)
  return Isc.load_file(path) if path.end_with?(".isc")
  DSL.parse(File.basename(path, ".imp")) # legacy
end
```

## Verification
```ruby
# Both should produce identical output:
Interscript.transliterate("alalc-amh-Ethi-Latn-1997", "ሀለ")     # .imp
Interscript.transliterate("alalc-amh-Ethi-Latn-1997", "ሀለ")     # .isc (if .isc exists)
```

## Autoload Registration
Add to `lib/interscript/isc.rb`:
```ruby
autoload :NodeAdapter, "interscript/isc/node_adapter"
```
