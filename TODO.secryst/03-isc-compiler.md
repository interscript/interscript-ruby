# 03 — ISC compiler: compile .isc to executable Ruby/JS

## Priority: MEDIUM

## Current State
- ISC files are parsed at runtime by the Parslet parser.
- For large CJK maps (40k+ lines), parsing takes 20-38 seconds.
- The Ruby DSL (.imp) is compiled to `Interscript::Node` objects via
  `instance_exec` — also not fast, but cached.

## Proposal
Build a compiler that transforms `.isc` source into an executable artifact:

### Ruby target
Compile `.isc` → `.rb` that constructs `Interscript::Node` objects directly:
```ruby
# Generated from foo.isc
Interscript::Node::Document.new.tap do |doc|
  doc.metadata = Interscript::Node::MetaData.new(...)
  doc.stages[:main] = Interscript::Node::Stage.new(...)
end
```

### JavaScript target
Compile `.isc` → `.js` that constructs equivalent JS objects.

### Distribution
- Ship compiled `.rb`/`.js` files alongside (or instead of) `.isc` source.
- The `.isc` source is for humans; the compiled artifact is for runtime.
- A `rake compile` task generates all artifacts from `.isc` sources.

## Benefits
1. **Performance**: No parser overhead at runtime — load a `.rb` file.
2. **Validation**: Compilation catches errors at build time, not runtime.
3. **Distribution**: Compiled files are deterministic and cacheable.

## Implementation
- New class: `Interscript::Isc::Compiler`
- Methods: `compile_to_ruby(tree)`, `compile_to_javascript(tree)`
- Integrates with existing `Interscript::Compiler::Ruby` and `::Javascript`.