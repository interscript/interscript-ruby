class Interscript::Node::Item < Interscript::Node
  attr_accessor :item
  def initialize item
    self.item = item
    self
  end

  def + other
    # puts "Interscript::Node::Item +(#{self.inspect}, #{other.inspect})"
    # res = Interscript::Node::Item.new 'placeholder'
    # puts res.inspects
    if other.class == Array
      Interscript::Node::Item::Group.new( self, *other)
    elsif other.class == String
      other = Interscript::Node::Item.new other
      Interscript::Node::Item::Group.new(self, other)
    else
      Interscript::Node::Item::Group.new(self, other)
    end
  end

  def to_hash
    { :class => self.class.to_s,
     :item => self.item}
   end

end

require "interscript/node/item/alias"
require "interscript/node/item/character"
require "interscript/node/item/group"
require "interscript/node/item/any"