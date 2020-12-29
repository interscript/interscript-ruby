class Interscript::DSL::Document
  attr_accessor :node

  def initialize(&block)
    @node = Interscript::Node::Document.new
  end

  %i{authority_id id language source_script
    destination_script name url creation_date
    adoption_date description character notes
    source confirmation_date}.each do |sym|
    define_method sym do |stuff|
      @node.metadata[sym] = stuff
    end
  end


  def metadata(&block)
    instance_eval(&block)
  end

  def tests(&block)
    instance_eval(&block)
  end

  def test(from,to)
    @node.tests << [from, to]
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


  def stage(&block)
    puts "stage() from #{self.inspect}" if $DEBUG
    stage = Interscript::DSL::Stage.new(&block)
    @node.stage = stage.node
  end
end
