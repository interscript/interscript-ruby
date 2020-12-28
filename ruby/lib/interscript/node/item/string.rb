class Interscript::Node::Item::String  < Interscript::Node::Item
  attr_accessor :data
  def initialize data
    self.data = data
  end

  def to_hash
    { :class => self.class.to_s,
      :char => self.data }
  end
end
