module Interscript::DSL::Group

  include Interscript::DSL::Items

  # method doubled in stage.rb
  def sub(from, to, **kargs, &block)
    puts "sub(#{from.inspect},#{to}, kargs = #{
      kargs.inspect
    }) from #{self.inspect}" if $DEBUG

    @children << Interscript::Node::Rule::Sub.new(from,to,**kargs)
  end

  def any(chars)
    puts "any(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::Any.new(chars)
  end
  
end