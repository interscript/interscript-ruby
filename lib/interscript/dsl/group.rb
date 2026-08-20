class Interscript::DSL::Group
  include Interscript::DSL::Items

  attr_accessor :node

  def initialize(&block)
    @node = Interscript::Node::Group.new
    instance_exec(&block)
  end

  def run(stage, **kwargs)
    if stage.class != Interscript::Node::Item::Stage
      raise Interscript::MapLogicError, "I::Node::Item::Stage expected, got #{stage.class}"
    end
    @node.children << Interscript::Node::Rule::Run.new(stage, **kwargs)
  end

  def sub(from, to, **kwargs, &block)
    if $DEBUG
      puts "sub(#{from.inspect},#{to}, kwargs = #{
        kwargs.inspect
      }) from #{inspect}"
    end

    rule = Interscript::Node::Rule::Sub.new(from, to, **kwargs)
    @node.children << rule
  end

  def upcase
    :upcase
  end

  def downcase
    :downcase
  end

  Interscript::Stdlib.available_functions.each do |fun|
    define_method fun do |**kwargs|
      puts "funcall(#{fun}, #{kwargs.inspect}) from #{inspect}" if $DEBUG

      rule = Interscript::Node::Rule::Funcall.new(fun, **kwargs)
      @node.children << rule
    end
  end

  def parallel(**kwargs, &block)
    puts "parallel(#{chars.inspect}) from #{inspect}" if $DEBUG
    group = Interscript::DSL::Group::Parallel.new(**kwargs, &block)
    @node.children << group.node
  end
end

class Interscript::DSL::Group
  autoload :Parallel, "interscript/dsl/group/parallel"
end
