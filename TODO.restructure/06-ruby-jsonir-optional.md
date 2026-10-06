# 06 — Ruby: keep JsonIR as optional export

## Priority: P2

## Status: COMPLETE

## Problem
The JsonIR compiler should remain available but not be the default
pipeline. Users who want pre-compiled JSON for performance can still
generate it.

## Implementation

JsonIR is autoloaded in `lib/interscript/compiler.rb`:
```ruby
class Interscript::Compiler
  autoload :Javascript, "interscript/compiler/javascript"
  autoload :Python, "interscript/compiler/python"
  autoload :Ruby, "interscript/compiler/ruby"
  autoload :JsonIR, "interscript/compiler/json_ir"
  ...
```

It's lazy-loaded — only loaded into memory when explicitly referenced.
The default `Interscript.transliterate` uses `Interscript::Interpreter`,
not JsonIR.

## Usage
```ruby
# Generate JSON IR from .isc (optional, not default)
require "interscript"
require "interscript/isc"
Interscript.load_path.unshift("maps")

src = File.read("maps/foo.isc")
tree = Interscript::Isc::Parser.parse(src, filename: "foo.isc")
doc = Interscript::Isc::DocumentBuilder.build(tree, filename: "foo.isc")
node = Interscript::Isc::NodeAdapter.to_interscript_node(doc)

compiler = Interscript::Compiler::JsonIR.new
compiler.compile(node)
File.write("foo.json", compiler.code)
```

## Verification
- JsonIR is autoloaded (lazy)
- Default `Interscript.transliterate` uses Interpreter
- All 289 .isc files transliterate correctly without JsonIR
