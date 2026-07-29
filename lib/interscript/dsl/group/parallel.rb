class Interscript::DSL::Group::Parallel < Interscript::DSL::Group
  def initialize(reverse_run: nil, &block)
    @node = Interscript::Node::Group::Parallel.new(reverse_run: reverse_run)
    instance_exec(&block)
  end
end
