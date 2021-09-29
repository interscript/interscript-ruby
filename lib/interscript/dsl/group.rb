class Interscript::DSL::Group
  include Interscript::DSL::Items

  attr_accessor :node

  def initialize(&block)
    @node = Interscript::Node::Group.new
    self.instance_exec(&block)
  end

  def run(stage, **kwargs)
    if stage.class != Interscript::Node::Item::Stage
      raise TypeError, "I::Node::Item::Stage expected, got #{stage.class}"
    end
    @node.children << Interscript::Node::Rule::Run.new(stage, **kwargs)
  end

  def sub(from, to, **kwargs, &block)
    puts "sub(#{from.inspect},#{to}, kwargs = #{
      kwargs.inspect
    }) from #{self.inspect}" if $DEBUG

    rule = Interscript::Node::Rule::Sub.new(from, to, **kwargs)
    @node.children << rule
  end

  def upcase; :upcase; end
  def downcase; :downcase; end

  Interscript::Stdlib.available_functions.each do |fun|
    define_method fun do |**kwargs|
      puts "funcall(#{fun}, #{kwargs.inspect}) from #{self.inspect}" if $DEBUG

      rule = Interscript::Node::Rule::Funcall.new(fun, **kwargs)
      @node.children << rule
    end
  end

  def parallel(**kwargs, &block)
    puts "parallel(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    group = Interscript::DSL::Group::Parallel.new(**kwargs, &block)
    @node.children << group.node
  end
end

require 'interscript/dsl/group/parallel'
