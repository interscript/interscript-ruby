class Interscript::Node::Document < Interscript::Node::Group

  attr_accessor :metadata, :tests, :dependencies, :aliases, :stage
  def initialize
    puts "Interscript::Node::Document.new " if $DEBUG
    @metadata = {}
    @tests = []
    @dependencies = {}
    @aliases = {}
    @stage = []

    
    %i{authority_id id language source_script 
      destination_script name url creation_date
      adoption_date description character notes
      source confirmation_date}.each do |sym|
      self.class.send(:define_method,sym) {|stuff|
         @metadata[sym] = stuff
       }
    end
  end

  def parse(filename)
    instance_eval File.read(filename)
  end




  def metadata(&block)
    instance_eval(&block)
  end




  def dependency(name, **kargs)
    puts "dependency(#{name.inspect}, #{kargs.inspect}" if $DEBUG
    self.dependencies[ kargs[:as] ] = {
      name: name,
      import: kargs[:import]||false }
  end



  def any(chars)
    puts "any(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::Any.new(chars)
  end


  def def_alias(name, thing)
    puts "def_alias(#{name.inspect}, #{thing.inspect})" if $DEBUG
    self.aliases[name] = thing
  end


  def test(from,to)
    @tests << [from, to]
  end

  def tests(&block)
    instance_eval(&block)
  end

  def stage(&block)
    puts "stage() from #{self.inspect}" if $DEBUG
    @stage << Interscript::Node::Stage.new(&block)
  end




  def to_hash
    {:class => self.class.to_s, :metadata => @metadata, :tests => @tests,
     :dependencies => @dependencies,
     :aliases => @aliases.each_with_object({}){ |pair,hash|
        hash[pair[0]] = pair[1].to_hash
      },
     :stage => @stage.map{|x| x.to_hash} }
  end




end
