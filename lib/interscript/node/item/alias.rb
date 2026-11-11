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

  def boundary_like?
    Interscript::Stdlib.boundary_like_alias?(name)
  end

  # rs parity (WO17): the deterministic parallel sort counts every
  # alias as 1 (0 for none) — rs Item::max_length treats Prim/Alias
  # uniformly, and resolving the expansion here would need document
  # context the sort site does not carry.
  def max_length
    if stdlib?
      [:none].include?(name) ? 0 : 1
    else
      1
    end
  end

  # Not implemented properly
  def downcase
    self
  end

  def upcase
    self
  end

  def first_string
    self
  end

  alias_method :nth_string, :first_string

  def to_hash
    {class: self.class.to_s,
     name: name,
     map: map}
  end

  def ==(other)
    super && name == other.name && map == other.map
  end

  def inspect
    if map
      "map.#{map}.#{name}"
    else
      name.to_s
    end
  end
end
