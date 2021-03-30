class Interscript::DSL::Stage < Interscript::DSL::Group
  def initialize(name = :main, &block)
    @node = Interscript::Node::Stage.new(name)
    self.instance_exec(&block)
  end
end
