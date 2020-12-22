class Interscript::Node::Document < Interscript::Node::Group
  #include Interscript::DSL::Document

  attr_accessor :metadata, :tests
  attr_accessor :dependencies, :aliases, :stage
  def initialize
    puts "Interscript::Node::Document.new " if $DEBUG
    @metadata = Interscript::Node::MetaData.new 
    @tests = Interscript::Node::Tests.new
    @dependencies = []
    @aliases = []
    @stage = []    
  end

  def to_hash
    {:class => self.class.to_s, :metadata => @metadata.to_hash,
      :tests => @tests.to_hash,
      :dependencies => @dependencies.map{|x| x.to_hash},
      :aliases => @aliases.map{|x| x.to_hash},
     :stage => @stage.map{|x| x.to_hash} }
  end

end