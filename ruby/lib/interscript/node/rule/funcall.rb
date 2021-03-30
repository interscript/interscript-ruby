class Interscript::Node::Rule::Funcall < Interscript::Node::Rule
  attr_accessor :name, :kwargs
  def initialize name, **kwargs
    @name = name
    @kwargs = kwargs
  end

  def to_hash
    { :class => self.class.to_s,
      :name => self.name,
      :kwargs => self.kwargs
    }
  end

  def inspect
    "#{@name} #{kwargs.inspect[1..-2]}"
  end
end
