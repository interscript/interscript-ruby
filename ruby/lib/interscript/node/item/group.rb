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
    out.verify!
    out
  end

  # Verify if a group is valid
  def verify!
    wrong = @children.find do |i|
      Interscript::Node::Item::Stage === i ||
      ! (Interscript::Node::Item === i) ||
      i.class == Interscript::Node::Item
    end

    if wrong
      raise TypeError, "An I::Node::Item::Group can't contain an #{wrong.class} item."
    end
  end

  def max_length
    @children.map { |i| i.max_length }.sum
  end

  def to_hash
    { :class => self.class.to_s,
      :children => self.children.map{|x| x.to_hash} }
  end
end
