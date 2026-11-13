# (...)
class Interscript::Node::Item::CaptureGroup < Interscript::Node::Item
  attr_accessor :data

  def initialize(data)
    data = Interscript::Node::Item.try_convert(data)
    @data = data
  end

  # rs parity (WO18 G1): the deterministic parallel sort needs a
  # max_length on every Item. A capture's length is its innards'
  # length (ts maxLengthOfItem: capture_group -> inner).
  def max_length
    data.max_length
  end

  def first_string
    data.first_string
  end

  def nth_string
    data.nth_string
  end

  def downcase
    dup.tap { |i| i.data = i.data.downcase }
  end

  def upcase
    dup.tap { |i| i.data = i.data.upcase }
  end

  def to_hash
    {class: self.class.to_s,
     data: data.to_hash}
  end

  def ==(other)
    super && data == other.data
  end

  def inspect
    "capture(#{@data.inspect})"
  end
end

# \1
class Interscript::Node::Item::CaptureRef < Interscript::Node::Item
  attr_accessor :id

  def initialize(id)
    @id = id
  end

  # rs parity (WO18 G1): a backreference matches one captured run.
  def max_length
    1
  end

  def first_string
    self
  end

  alias_method :nth_string, :first_string

  def to_hash
    {class: self.class.to_s,
     id: id}
  end

  def ==(other)
    super && id == other.id
  end

  def inspect
    "ref(#{@id.inspect})"
  end
end
