class Interscript::Node
  # Autoload all node types. Adding a new node type = one autoload
  # line here. No require_relative (OCP).
  autoload :Group, "interscript/node/group"
  autoload :Document, "interscript/node/document"
  autoload :MetaData, "interscript/node/metadata"
  autoload :AliasDef, "interscript/node/alias_def"
  autoload :Dependency, "interscript/node/dependency"
  autoload :Tests, "interscript/node/tests"
  autoload :Stage, "interscript/node/stage"
  autoload :Rule, "interscript/node/rule"
  autoload :Item, "interscript/node/item"

  def initialize
    raise NotImplementedError, "You can't construct a Node directly"
  end

  def ==(other)
    self.class == other.class
  end

  def to_hash
    {class: self.class.to_s,
     question: "is something missing?"}
  end
end
