class Interscript::DSL::Stage < Interscript::DSL::Group

  def initialize(&block)
    @node = Interscript::Node::Stage.new
    self.instance_exec(&block)
    @node
  end

end