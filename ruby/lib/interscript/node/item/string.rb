class Interscript::Node::Item::String < Interscript::Node::Item
  attr_accessor :data
  def initialize data
    self.data = data
  end

  def to_hash
    { :class => self.class.to_s,
      :data => self.data }
  end

  def max_length
    self.data.length
  end

  def first_string
    self.data
  end

  def downcase; self.dup.tap { |i| i.data = i.data.downcase }; end
  def upcase; self.dup.tap { |i| i.data = i.data.upcase }; end

  alias nth_string first_string

  def + other
    if self.data == ""
      Interscript::Node::Item.try_convert(other)
    elsif Interscript::Node::Item::String === self &&
      (Interscript::Node::Item::String === other || ::String === other)

      other = Interscript::Node::Item.try_convert(other)

      Interscript::Node::Item::String.new(self.data + other.data)
    else
      super
    end
  end

  def inspect
    @data.inspect
  end
end

# stdext
class String
  alias plus_before_interscript +
  def + other
    if Interscript::Node === other
      Interscript::Node::Item.try_convert(self) + other
    else
      self.plus_before_interscript(other)
    end
  end
end
