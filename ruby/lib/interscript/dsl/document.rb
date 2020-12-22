module Interscript::DSL::Document


  %i{authority_id id language source_script 
    destination_script name url creation_date
    adoption_date description character notes
    source confirmation_date}.each do |sym|
    self.send(:define_method,sym) {|stuff|
       @metadata_data[sym] = stuff
     }
  end


  def metadata(&block)
    instance_eval(&block)
  end



  def test(from,to)
    @tests_data << [from, to]
  end

  def tests(&block)
    instance_eval(&block)
  end


  def dependency(full_name, **kargs)
    puts "dependency(#{name.inspect}, #{kargs.inspect}" if $DEBUG
    dep = Interscript::Node::Dependency.new
    dep.name = kargs[:as]
    dep.full_name = full_name
    dep.import = kargs[:import] || false
    @dependencies << dep
  end


  def def_alias(name, chars)
    puts "def_alias(#{name.inspect}, #{thing.inspect})" if $DEBUG
    @aliases << Interscript::Node::Alias.new(name,chars)

  end


  def stage(&block)
    puts "stage() from #{self.inspect}" if $DEBUG
    @stage_data << Interscript::Node::Stage.new(&block)
  end



end

