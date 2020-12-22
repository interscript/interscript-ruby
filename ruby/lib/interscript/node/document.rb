class Interscript::Node::Document < Interscript::Node::Group
  include Interscript::DSL::Document

  attr_accessor :metadata_data, :tests_data
  attr_accessor :dependencies, :aliases, :stage_data
  def initialize
    puts "Interscript::Node::Document.new " if $DEBUG
    @metadata_data = Interscript::Node::MetaData.new 
    @tests_data = Interscript::Node::Tests.new
    @dependencies = []
    @aliases = []
    @stage_data = []    
  end

  def parse(filename)
    instance_eval File.read(filename)
  end

  def to_hash
    {:class => self.class.to_s, :metadata => @metadata_data.to_hash,
      :tests => @tests_data.to_hash,
      :dependencies => @dependencies.map{|x| x.to_hash},
      :aliases => @aliases.map{|x| x.to_hash},
     :stage => @stage_data.map{|x| x.to_hash} }
  end

end