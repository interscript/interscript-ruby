class Interscript::Node::Group < Interscript::Node
  attr_accessor :children

  def initialize
    @children = []
  end

  def to_hash
    { :class => self.class.to_s,
      :children => @children.map{|x| x.to_hash} }
  end
end

require "interscript/node/group/parallel"
require "interscript/node/group/sequential"
