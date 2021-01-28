# (...)
class Interscript::Node::Item::CaptureGroup < Interscript::Node::Item
  attr_accessor :data

  def initialize(data)
    data = Interscript::Node::Item.try_convert(data)
    @data = data
  end

  def to_hash
    { :class => self.class.to_s,
      :data => self.data.to_hash }
  end
end

# \1
class Interscript::Node::Item::CaptureRef < Interscript::Node::Item
  attr_accessor :id

  def initialize(id)
    @id = id
  end

  def to_hash
    { :class => self.class.to_s,
      :id => self.id }
  end
end
