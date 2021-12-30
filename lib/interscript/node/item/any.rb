class Interscript::Node::Item::Any < Interscript::Node::Item
  attr_accessor :value
  def initialize data
    case data
    when Array, ::String, Range
      self.value = data
    when Interscript::Node::Item::Group # debug alalc-ara-Arab-Latn-1997  line 683
      self.value = data.children
    when Interscript::Node::Item::Alias # debug mofa-jpn-Hrkt-Latn-1989 line 116
      self.value = Interscript::Stdlib::ALIASES[data.name]
    else
      puts data.inspect
      raise Interscript::MapLogicError, "Wrong type #{data[0].class}, excepted Array, String or Range"
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

  def downcase; self.class.new(self.data.map(&:downcase)); end
  def upcase; self.class.new(self.data.map(&:upcase)); end

  def first_string
    case @value
    when Array
      Interscript::Node::Item.try_convert(value.first).first_string
    when ::String
      value[0]
    when Range
      value.begin
    end
  end

  def nth_string
    return first_string unless $select_nth_string

    d = data
    Fiber.yield(:prepare)
    id = Fiber.yield(:select_nth_string, d.count, self.hash)
    Fiber.yield(:selection)
    Interscript::Node::Item.try_convert(value[id]).nth_string
  end

  def max_length
    self.data.map(&:max_length).max
  end

  def to_hash
    hash = { :class => self.class.to_s }

    case @value
    when Array
      hash[:type] = "Array"
      hash[:data] = data.map { |i| i.to_hash }
    when ::String
      hash[:type] = "String"
      hash[:data] = @value
    when Range
      hash[:type] = "Range"
      hash[:data] = [@value.begin, @value.end]
    when NilClass
      hash[:type] = "nil (bug)"
    end

    hash
  end

  def ==(other)
    super && self.data == other.data
  end

  def inspect
    "any(#{value.inspect})"
  end
end
