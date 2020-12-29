class Interscript::Node::Item::Alias < Interscript::Node::Item
  attr_accessor :name
  def initialize(name)
    self.name = name
  end

  def to_hash
    { :class => self.class.to_s,
      :name => name }
  end
end
