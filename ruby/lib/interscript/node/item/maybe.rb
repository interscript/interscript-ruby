# code based on Item::Capture atm, not sure if that is the right one.
class Interscript::Node::Item::Maybe < Interscript::Node::Item
  attr_accessor :data
  def initialize data
    data = Interscript::Node::Item.try_convert(data)
    @data = data
  end

  def first_string
    data.first_string
  end

  def max_length
    data.max_length
  end

  def to_hash
    { :class => self.class.to_s,
      :data => self.data.to_hash }
  end
end
class Interscript::Node::Item::MaybeN < Interscript::Node::Item::Maybe
end
class Interscript::Node::Item::Some < Interscript::Node::Item::Maybe
end