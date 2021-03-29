class Interscript::Node::MetaData < Interscript::Node
  attr_accessor :data
  def initialize data={}
    @data = data
  end

  def []=(k,v)
    @data[k] = v
  end
  def [](k)
    @data[k]
  end

  def to_hash
    {:class => self.class.to_s,
      :data => @data}
  end
end
