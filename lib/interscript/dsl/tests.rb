class Interscript::DSL::Tests
  attr_accessor :node

  def initialize(&block)
    @node = Interscript::Node::Tests.new
    self.instance_exec(&block)
  end

  def test(from, to, reverse_run: nil)
    @node << [from, to, reverse_run]
  end
end
