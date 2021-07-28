class Interscript::Node::Tests < Interscript::Node
  attr_accessor :data
  def initialize data=[]
    @data = data
  end

  def <<(pair)
    @data << pair
  end

  def reverse
    self.class.new(data.map(&:reverse))
  end

  def to_hash
    { :class => self.class.to_s,
      :data => @data }
  end
end
