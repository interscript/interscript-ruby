class Interscript::Node::Item::Alias < Interscript::Node::Item
  attr_accessor :name
  attr_accessor :map
  def initialize(name, map: nil)
    self.name = name
    self.map = map
  end

  def stdlib?
    !map && Interscript::Stdlib::ALIASES.has_key?(name)
  end

  def max_length
    if stdlib?
      (name == :none) ? 0 : 1
    else
      raise NotImplementedError, "can't get a max length of this alias"
    end
  end

  def first_string
    self
  end

  def to_hash
    { :class => self.class.to_s,
      :name => name,
      :map => map,
    }
  end
end
