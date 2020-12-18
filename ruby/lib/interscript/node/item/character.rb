class Interscript::Node::Item::Character < Interscript::Node::Item
  attr_accessor :char
  def initialize char
    self.char = char
  end

  def to_hash
    { :class => self.class.to_s,
      :char => self.char}
  end
end
