class Interscript::Node::Tests < Interscript::Node
  attr_accessor :data
  def initialize data=[]
    @data = data
  end

  def <<(pair)
    @data << pair
  end

  def reverse
    self.class.new(data.map do |from,to,reverse_run|
      [to, from, reverse_run == nil ? nil : !reverse_run]
    end)
  end

  def ==(other)
    super && self.data == other.data
  end

  def to_hash
    { :class => self.class.to_s,
      :data => @data }
  end
end
