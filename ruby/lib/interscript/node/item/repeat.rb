class Interscript::Node::Item::Repeat < Interscript::Node::Item
  attr_accessor :data
  def initialize data
    data = Interscript::Node::Item.try_convert(data)
    @data = data
  end

  def first_string
    data.first_string
  end

  def nth_string
    data.nth_string
  end

  def max_length
    data.max_length
  end

  def to_hash
    { :class => self.class.to_s,
      :data => self.data.to_hash }
  end

  def inspect
    str = case self
    when Interscript::Node::Item::Maybe
      "maybe"
    when Interscript::Node::Item::MaybeSome
      "maybe_some"
    when Interscript::Node::Item::Some
      "some"
    end
    "#{str}(#{@data.inspect})"
  end
end

class Interscript::Node::Item::Maybe < Interscript::Node::Item::Repeat; end
class Interscript::Node::Item::MaybeSome < Interscript::Node::Item::Repeat; end
class Interscript::Node::Item::Some < Interscript::Node::Item::Repeat; end
