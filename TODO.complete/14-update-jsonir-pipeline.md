# 14 — Update JsonIR pipeline for .isc files

## Problem
The JsonIR compiler (`Interscript::Compiler::JsonIR`) generates JSON IR
from `Interscript::Node::Document` objects. These are produced by
`Interscript::DSL.parse` which reads `.imp` files.

Now that maps repo has only `.isc` files, the pipeline must use:
1. `Interscript::Isc::Parser` to parse `.isc` source
2. `Isc::DocumentBuilder` to get document hash
3. `Isc::NodeAdapter` to convert to `Node::Document`
4. `Compiler::JsonIR` to generate JSON IR

## Status
Already implemented: `Interscript::Compiler.call` dispatches to
`parse_isc` for `.isc` files. The pipeline works end-to-end.

## Verification
```ruby
Interscript.load_path.unshift("maps")
result = Interscript.transliterate("alalc-amh-Ethi-Latn-1997", "ሀ")
# Uses .isc → Parser → DocumentBuilder → NodeAdapter → Interpreter
```

## Remaining
- Website's map generation script needs to point at .isc files
- CI pipeline for regenerating JSON IR from .isc
