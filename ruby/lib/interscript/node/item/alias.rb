class Interscript::Node::Item::Alias < Interscript::Node::Item
  attr_accessor :name
  attr_accessor :map
  def initialize(name, map: nil)
    self.name = name
    self.map = map
  end

  def max_length
    raise NotImplementedError, "max_length not implemented for alias"
  end

  def to_hash
    { :class => self.class.to_s,
      :name => name,
      :map => map,
    }
  end
end
