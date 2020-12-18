class Interscript::Node::Item::Group < Interscript::Node::Item
  attr_accessor :children
  def initialize *children
    @children = children
  end

  def +(item)
    if item.class == String
      item = Interscript::Node::Item.new item
    end
    @children << item
    self
  end

  def to_hash
    { :class => self.class.to_s,
      :children => self.children.map{|x| x.to_hash}}
  end

end
