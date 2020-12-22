class Interscript::Node::Tests < Interscript::Node
  attr_accessor :data
  def initialize data=[]
    @data = data
  end

  def <<(pair)
    @data << pair
  end

  def to_hash
    {:class => self.class.to_s,
      :data => @data}
  end
end
