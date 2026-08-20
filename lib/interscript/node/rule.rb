class Interscript::Node::Rule < Interscript::Node
  # Autoload all rule types (OCP: new rule type = one autoload).
  autoload :Sub, "interscript/node/rule/sub"
  autoload :Run, "interscript/node/rule/run"
  autoload :Funcall, "interscript/node/rule/funcall"

  def ==(other)
    super && reverse_run == other.reverse_run
  end
end
