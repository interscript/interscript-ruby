class Interscript::DSL::Document
  include Interscript::DSL::Items # Items are needed for alias definitions.. should we improve on that?

  attr_accessor :node

  def initialize(&block)
    @node = Interscript::Node::Document.new
  end

  def metadata(&block)
    metadata = Interscript::DSL::Metadata.new(&block)
    @node.metadata = metadata.node
  end

  def tests(&block)
    tests = Interscript::DSL::Tests.new(&block)
    @node.tests = tests.node
  end

  def dependency(full_name, **kargs)
    puts "dependency(#{name.inspect}, #{kargs.inspect}" if $DEBUG
    dep = Interscript::Node::Dependency.new
    dep.name = kargs[:as]
    dep.full_name = full_name
    dep.import = kargs[:import] || false
    @node.dependencies << dep
  end

  def def_alias(name, value)
    puts "def_alias(#{name.inspect}, #{thing.inspect})" if $DEBUG
    @node.aliases << Interscript::Node::AliasDef.new(name, value)
  end

  def stage(name = :main, &block)
    puts "stage(#{name}) from #{self.inspect}" if $DEBUG
    stage = Interscript::DSL::Stage.new(name, &block)
    @node.stage = stage.node
  end
end
