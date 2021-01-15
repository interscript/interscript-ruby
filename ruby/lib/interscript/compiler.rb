# An Interscript compiler interface
class Interscript::Compiler
  attr_accessor :code, :fname

  def initialize(fname)
    @fname = fname
    map = Interscript::parse(fname)
    compile(map)
    self
  end

  def compile(map)
    raise NotImplementedError, "Compile method on #{self.class} is not implemented"
  end

  # Execute a map
  def call
    raise NotImplementedError, "Call class on #{self.class} is not implemented"
  end
end
