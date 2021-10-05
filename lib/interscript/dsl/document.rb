class Interscript::DSL::Document
  include Interscript::DSL::SymbolMM

  attr_accessor :node

  def initialize(name = nil, &block)
    @node = Interscript::Node::Document.new
    @node.name = name if name
    self.instance_exec &block if block_given?
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
    @node.aliases.transform_values { |v| v.doc_name = @node.name; v }
  end

  def dependency(full_name, **kargs)
    puts "dependency(#{name.inspect}, #{kargs.inspect}" if $DEBUG
    dep = Interscript::Node::Dependency.new
    dep.name = kargs[:as]
    dep.full_name = full_name
    dep.import = kargs[:import] || false

    dep.document = Interscript::DSL.parse(full_name)
    @node.dependencies << dep
    @node.dep_aliases[dep.name] = dep if dep.name
  end

  def stage(name = :main, dont_reverse: false, &block)
    puts "stage(#{name}) from #{self.inspect}" if $DEBUG
    stage = Interscript::DSL::Stage.new(name, &block)
    stage.node.doc_name = @node.name
    stage.node.dont_reverse = dont_reverse
    @node.stages[name] = stage.node
  end
end
