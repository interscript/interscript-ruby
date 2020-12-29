class Interscript::Node::Item::Any < Interscript::Node::Item
  attr_accessor :value
  def initialize data
    case data
    when Array, ::String, Range
      self.value = data
    else
      raise TypeError, "Wrong type #{data[0].class}, excepted Array, String or Range"
    end
  end

  def data
    case @value
    when Array
      value.map { |i| Interscript::Node::Item.try_convert(i) }
    when ::String
      value.split("").map { |i| Interscript::Node::Item.try_convert(i) }
    when Range
      value.map { |i| Interscript::Node::Item.try_convert(i) }
    end
  end

  def max_length
    self.data.map(&:max_length).max
  end

  def to_hash
    { :class => self.class.to_s,
      :data => self.data.map { |i| i.to_hash } }
  end
end
