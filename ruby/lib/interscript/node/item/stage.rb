class Interscript::Node::Item::Stage < Interscript::Node::Item
  attr_accessor :name
  attr_accessor :map
  def initialize(name, map: nil)
    self.name = name
    self.map = map
  end

  def to_hash
    { :class => self.class.to_s,
      :name => name,
      :map => map,
    }
  end

  def inspect
    if map
      "map.#{@map}.stage.#{@name}"
    else
      "stage.#{@name}"
    end
  end
end
