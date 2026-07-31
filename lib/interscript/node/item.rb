class Interscript::Node::Item < Interscript::Node
  attr_accessor :item
  def initialize item
    raise NotImplementedError, "You can't construct a Node::Item directly"
  end

  def + other
    this = self

    this = this.children if Interscript::Node::Item::Group === this
    other = other.children if Interscript::Node::Item::Group === other

    this = Array(this)
    other = Array(other)

    this = this.map { |i| Interscript::Node::Item.try_convert(i) }
    other = other.map { |i| Interscript::Node::Item.try_convert(i) }

    middle = []

    if Interscript::Node::Item::String === this.last &&
        Interscript::Node::Item::String === other.first

      middle = [this.last + other.first]
      this = this[0..-2]
      other = this[1..-1]
    end

    g = Interscript::Node::Item::Group.new(*this, *middle, *other)
    g.verify!
    g
  end

  def to_hash
    {class: self.class.to_s,
     item: item}
  end

  def ==(other)
    super
  end

  def self.try_convert(i)
    i = Interscript::Node::Item::String.new(i) if i.class == ::String
    raise Interscript::MapLogicError, "Wrong type #{i.class}, expected I::Node::Item" unless Interscript::Node::Item === i
    i
  end
end

class Interscript::Node::Item
  # Autoload all item types (OCP: new item type = one autoload).
  autoload :Alias, "interscript/node/item/alias"
  autoload :String, "interscript/node/item/string"
  autoload :Group, "interscript/node/item/group"
  autoload :Any, "interscript/node/item/any"
  autoload :Stage, "interscript/node/item/stage"
  autoload :CaptureGroup, "interscript/node/item/capture"
  autoload :Repeat, "interscript/node/item/repeat"
  # Maybe, MaybeSome, Some are subclasses of Repeat defined in
  # the same file. Autoload points to repeat.rb which defines all of them.
  autoload :Maybe, "interscript/node/item/repeat"
  autoload :MaybeSome, "interscript/node/item/repeat"
  autoload :Some, "interscript/node/item/repeat"
end
