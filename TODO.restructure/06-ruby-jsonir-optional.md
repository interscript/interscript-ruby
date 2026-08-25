# 06 — Ruby: keep JsonIR as optional export

## Priority: P2

## Problem
The JsonIR compiler should remain available but not be the default
pipeline. Users who want pre-compiled JSON for performance can still
generate it.

## Design
```ruby
# Generate JSON IR from .isc (optional, not default)
Interscript.load_path.unshift("maps")
doc = Interscript.parse_isc("maps/foo.isc")  # Parse .isc
node = Interscript::Isc::NodeAdapter.to_interscript_node(doc)
json = Interscript::Compiler::JsonIR.compile(node)
File.write("foo.json", json)
```

## No code change needed
The existing `Interscript::Compiler::JsonIR` already works with
Node::Document objects. The NodeAdapter converts .isc → Node.
So the pipeline `.isc → parse → NodeAdapter → JsonIR` already works.

## Verification
```ruby
# Generate IR from .isc and compare with old .json
node = Isc::NodeAdapter.to_interscript_node(
  Isc::DocumentBuilder.build(
    Isc::Parser.parse(File.read("maps/foo.isc"))))
ir = Interscript::Compiler::JsonIR.compile(node)
old_ir = JSON.parse(File.read("public/maps/foo.json"))
# ir and old_ir should be equivalent
```
