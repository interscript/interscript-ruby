class Interscript::Node::Item::Group < Interscript::Node::Item
  attr_accessor :children

  def initialize *children
    @children = children.map do |i|
      Interscript::Node::Item::String.new(i) if i.class == ::String
    end
  end

  def +(item)
    item = Interscript::Node::Item::String.new(item) if item.class == ::String
    out = self.dup
    out.children << item
    out
  end

  def to_hash
    { :class => self.class.to_s,
      :children => self.children.map{|x| x.to_hash} }
  end
end
