class Interscript::Node::Group < Interscript::Node
  attr_accessor :children, :reverse_run

  def initialize(reverse_run: nil)
    @reverse_run = reverse_run
    @children = []
  end

  def reorder_children(source,target)
    @children[source], @children[target] = @children[target], @children[source]
    self
  end

  def apply_order(order)
    children_new = [nil] * @children.size
    order.each_with_index do |pos,idx|
      children_new[idx] = @children[pos]
    end
    @children = children_new
    #@children[source], @children[target] = @children[target], @children[source]
    self
  end

  def reverse
    self.class.new(reverse_run: reverse_run.nil? ? nil : !reverse_run).tap do |r|
      r.children = self.children.reverse.map(&:reverse)
    end
  end

  def to_hash
    { :class => self.class.to_s,
      :children => @children.map{|x| x.to_hash} }
  end

  def inspect
    @children.map(&:inspect).join("\n").gsub(/^/, "  ")
  end
end

require "interscript/node/group/parallel"
require "interscript/node/group/sequential"
