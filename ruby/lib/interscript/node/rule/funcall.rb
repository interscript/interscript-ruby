class Interscript::Node::Rule::Funcall < Interscript::Node::Rule
  attr_accessor :name, :kwargs, :reverse_run
  def initialize name, reverse_run: nil, **kwargs
    @name = name
    @reverse_run = reverse_run
    @kwargs = kwargs
  end

  def to_hash
    { :class => self.class.to_s,
      :name => self.name,
      :kwargs => self.kwargs
    }
  end

  def reverse
    self.class.new(Interscript::Stdlib.reverse_function[@name.to_sym],
      reverse_run: reverse_run.nil? ? nil : !reverse_run, **kwargs)
  end

  def inspect
    "#{@name} #{kwargs.inspect[1..-2]}"
  end
end
