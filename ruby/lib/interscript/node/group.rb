class Interscript::Node::Group < Interscript::Node
  include Interscript::DSL::Group

  attr_accessor :children

  def initialize *children, &block
    @children = children

    if block_given?
      instance_eval(&block)
    end
    self
  end




  def to_hash
    {:class => self.class.to_s,
      :children => @children.map{|x| x.to_hash}}
  end


end

require "interscript/node/group/parallel"
require "interscript/node/group/sequential"
