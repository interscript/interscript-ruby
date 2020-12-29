class Interscript::Node::Item::Group < Interscript::Node::Item
  attr_accessor :children

  def initialize *children
    @children = children.flatten.map do |i|
      Interscript::Node::Item.try_convert(i)
    end
  end

  def +(item)
    item = Interscript::Node::Item.try_convert(item)
    out = self.dup
    out.children << item
    out
  end

  def to_hash
    { :class => self.class.to_s,
      :children => self.children.map{|x| x.to_hash} }
  end
end
