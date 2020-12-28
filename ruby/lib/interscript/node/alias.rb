class Interscript::Node::Alias < Interscript::Node
  attr_accessor :name, :data

  def initialize(name, chars)
    @name = name
    @data = data
  end

  def to_hash
    { :class => self.class.to_s,
      :name => @name,
      :data => @data.to_hash }
  end
end
