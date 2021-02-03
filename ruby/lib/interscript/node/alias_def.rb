class Interscript::Node::AliasDef < Interscript::Node
  attr_accessor :name, :data, :doc_name

  def initialize(name, data)
    data = Interscript::Node::Item.try_convert(data)
    @name = name
    @data = data
  end

  def to_hash
    { :class => self.class.to_s,
      :name => @name,
      :data => @data.to_hash }
  end
end
