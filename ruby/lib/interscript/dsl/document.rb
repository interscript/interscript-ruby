class Interscript::DSL::Document
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

  def aliases(&block)
    aliases = Interscript::DSL::Aliases.new(&block)
    @node.aliases = aliases.node
  end

  def dependency(full_name, **kargs)
    puts "dependency(#{name.inspect}, #{kargs.inspect}" if $DEBUG
    dep = Interscript::Node::Dependency.new
    dep.name = kargs[:as]
    dep.full_name = full_name
    dep.import = kargs[:import] || false

    dep.document = Interscript::DSL.parse(full_name)
    @node.dependencies << dep
  end

  def stage(name = :main, &block)
    puts "stage(#{name}) from #{self.inspect}" if $DEBUG
    stage = Interscript::DSL::Stage.new(name, &block)
    @node.stage = stage.node
  end
end
