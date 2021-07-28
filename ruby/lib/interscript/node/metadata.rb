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

  def reverse
    self.class.new(data: data.dup).tap do |rmd|
      rmd[:source_script], rmd[:destination_script] = rmd[:destination_script], rmd[:source_script]
    end
  end

  def to_hash
    {:class => self.class.to_s,
      :data => @data}
  end
end
