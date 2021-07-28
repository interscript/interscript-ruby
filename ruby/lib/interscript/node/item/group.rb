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
    if Interscript::Node::Item::Group === item
      out.children += item.children
    else
      out.children << item
    end
    out.verify!
    out
  end

  def compact
    out = self.dup do |n|
      n.children = n.children.reject do |i|
        (Interscript::Node::Alias === i && i.name == :none) ||
        (Interscript::Node::String === i && i.data == "")
      end
    end

    if out.children.count == 0
      Interscript::Node::Alias.new(:none)
    elsif out.children.count == 1
      out.children.first
    else
      out
    end
  end

  def downcase; self.dup.tap { |i| i.children = i.children.map(&:downcase) }; end
  def upcase; self.dup.tap { |i| i.children = i.children.map(&:upcase) }; end

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

  def first_string
    self.children.map(&:first_string).reduce(&:+)
  end

  def nth_string
    self.children.map(&:nth_string).reduce(&:+)
  end

  def max_length
    @children.map { |i| i.max_length }.sum
  end

  def to_hash
    { :class => self.class.to_s,
      :children => self.children.map{|x| x.to_hash} }
  end

  def inspect
    @children.map(&:inspect).join("+")
  end
end
