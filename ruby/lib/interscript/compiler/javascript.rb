class Interscript::Compiler::Javascript
  def compile(map)
    @code = "function(string) { return ''; }"
  end

  def call
    # ExecJS thing
    # Also load the runtime (stdlib)
    raise NotImplementedError
  end
end
