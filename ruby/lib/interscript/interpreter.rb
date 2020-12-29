class Interscript::Interpreter < Interscript::Compiler
  def compile(map)
    @map = map
    self
  end

  def call
    # Here will be the main procedure of the interpreter
  end
end
