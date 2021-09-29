class Interscript::Node::Rule < Interscript::Node
  def ==(other)
    super && self.reverse_run == other.reverse_run
  end
end

require "interscript/node/rule/sub"
require "interscript/node/rule/run"
require "interscript/node/rule/funcall"
