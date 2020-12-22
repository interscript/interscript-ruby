class Interscript::Node::Alias < Interscript::Node
  attr_accessor :name, :chars

  def initialize(name, chars)
    @name = name
    @chars = chars
  end

  def to_hash
    {:class => self.class.to_s,
      :name => @name,
      :chars => @chars.to_hash}
  end
end
