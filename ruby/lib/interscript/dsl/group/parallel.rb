class Interscript::DSL::Group::Parallel < Interscript::DSL::Group

  def initialize(&block)
    @node = Interscript::Node::Group::Parallel.new
    self.instance_exec(&block)
  end

end