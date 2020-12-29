class Interscript::Node::Document < Interscript::Node::Group
  attr_accessor :metadata, :tests
  attr_accessor :dependencies, :aliases, :stage

  def initialize
    puts "Interscript::Node::Document.new " if $DEBUG
    @metadata = nil
    @tests = nil
    @dependencies = []
    @aliases = []
    @stage = Interscript::Node::Stage.new
  end

  def to_hash
    { :class => self.class.to_s, :metadata => @metadata.to_hash,
      :tests => @tests.to_hash,
      :dependencies => @dependencies.map{|x| x.to_hash},
      :aliases => @aliases.map{|x| x.to_hash},
      :stage => @stage.to_hash }
  end
end
