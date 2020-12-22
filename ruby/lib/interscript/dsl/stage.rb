module Interscript::DSL::Stage

  include Interscript::DSL::Items
  include Interscript::DSL::Group 
  
  #doesn't do anything yet
  def map(*args)
    {}
  end
  def run(*args)
    nil
  end

  def parallel(&block)
    puts "parallel(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    @children << Interscript::Node::Group::Parallel.new(&block)
  end

end