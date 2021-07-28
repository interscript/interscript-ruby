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

  def max_length
    if stdlib?
      ([:none].include? name) ? 0 : 1
    else
      return 1 if name == :unicode_hangul
      raise NotImplementedError, "can't get a max length of this alias"
    end
  end

  # Not implemented properly
  def downcase; self; end
  def upcase; self; end

  def first_string
    self
  end

  alias nth_string first_string

  def to_hash
    { :class => self.class.to_s,
      :name => name,
      :map => map,
    }
  end

  def inspect
    if map
      "map.#{map}.#{name}"
    else
      "#{name}"
    end
  end
end
