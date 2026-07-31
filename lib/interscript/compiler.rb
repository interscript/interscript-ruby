# An Interscript compiler interface
class Interscript::Compiler
  # Autoload all compiler variants (OCP: new compiler = one autoload).
  autoload :Javascript, "interscript/compiler/javascript"
  autoload :Python, "interscript/compiler/python"
  autoload :Ruby, "interscript/compiler/ruby"
  autoload :JsonIR, "interscript/compiler/json_ir"

  attr_accessor :code

  def self.call(map, **kwargs)
    if String === map
      map = Interscript::DSL.parse(map)
    end
    compiler = new
    compiler.compile(map, **kwargs)
    compiler
  end

  def compile(map)
    raise NotImplementedError, "Compile method on #{self.class} is not implemented"
  end

  # Execute a map
  def call
    raise NotImplementedError, "Call class on #{self.class} is not implemented"
  end
end
