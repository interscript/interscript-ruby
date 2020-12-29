class Interscript::Node::Item < Interscript::Node
  attr_accessor :item
  def initialize item
    raise NotImplementedError, "You can't construct a Node::Item directly"
  end

  def + other
    this = self

    this  = this.children  if Interscript::Node::Item::Group === this
    other = other.children if Interscript::Node::Item::Group === other

    this  = Array(this)
    other = Array(other)

    this  = this.map  { |i| Interscript::Node::Item.try_convert(i) }
    other = other.map { |i| Interscript::Node::Item.try_convert(i) }

    middle = []

    if Interscript::Node::Item::String === this.last &&
       Interscript::Node::Item::String === other.first

       middle = [this.last + other.first]
       this = this[0..-2]
       other = this[1..-1]
    end

    Interscript::Node::Item::Group.new(*this, *middle, *other)
  end

  def to_hash
    { :class => self.class.to_s,
      :item => self.item }
   end

   def self.try_convert(i)
     i = Interscript::Node::Item::String.new(i) if i.class == ::String
     raise TypeError, "Wrong type #{i.class}, expected I::Node::Item" unless Interscript::Node::Item === i
     i
   end
end

require "interscript/node/item/alias"
require "interscript/node/item/string"
require "interscript/node/item/group"
require "interscript/node/item/any"
