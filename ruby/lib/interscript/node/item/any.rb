class Interscript::Node::Item::Any < Interscript::Node::Item
  attr_accessor :chars
  def initialize chars
    self.chars = chars
  end

  def to_hash
    { :class => self.class.to_s,
      :chars => self.chars }
  end

end
