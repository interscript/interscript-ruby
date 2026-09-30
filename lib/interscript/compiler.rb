# An Interscript compiler interface
class Interscript::Compiler
  # Autoload all compiler variants (OCP: new compiler = one autoload).
  autoload :Javascript, "interscript/compiler/javascript"
  autoload :Python, "interscript/compiler/python"
  autoload :Ruby, "interscript/compiler/ruby"
  autoload :JsonIR, "interscript/compiler/json_ir"

  attr_accessor :code

  def self.call(map, **kwargs)
    # DSL.parse locates, dispatches .isc and caches the parsed document —
    # calling parse_isc here re-ran a full grammar parse on every
    # compiler instantiation.
    map = Interscript::DSL.parse(map) if String === map
    compiler = new
    compiler.compile(map, **kwargs)
    compiler
  end

  # Parse an ISC source file into an Interscript::Node::Document.
  # This bridges the new ISC format to the existing runtime.
  def self.parse_isc(path)
    source = File.read(path, encoding: "UTF-8")
    filename = File.basename(path)
    tree = Interscript::Isc::Parser.parse(source, filename: filename)
    doc = Interscript::Isc::DocumentBuilder.build(tree, filename: filename)
    Interscript::Isc::NodeAdapter.to_interscript_node(doc)
  end

  def compile(map)
    raise NotImplementedError, "Compile method on #{self.class} is not implemented"
  end

  # Execute a map
  def call
    raise NotImplementedError, "Call class on #{self.class} is not implemented"
  end
end
