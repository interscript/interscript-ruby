class Interscript::Node::Item::Any < Interscript::Node::Item
  attr_accessor :data
  def initialize *data
    if data.length > 1
      self.data = data.map { |i| Interscript::Node::Item.try_convert(i) }
    elsif Array === data[0]
      self.data = data[0].split("").map { |i| Interscript::Node::Item.try_convert(i) }
    elsif String === data[0]
      self.data = data[0].split("").map { |i| Interscript::Node::Item.try_convert(i) }
    elsif Range === data[0]
      self.data = data[0].map { |i| Interscript::Node::Item.try_convert(i) }
    else
      raise TypeError, "Wrong type #{data[0].class}, excepted Array, String or Range"
    end
  end

  def to_hash
    { :class => self.class.to_s,
      :chars => self.chars.map { |i| i.to_hash } }
  end
end
