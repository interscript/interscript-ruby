
class Interscript::Node

  def initialize
  end


  def method_missing(name, *args, **kargs, &block)
    puts "method_missing(#{
          name.inspect
        }, #{
          args.inspect
        },) from #{self.inspect} "#,@mm_level=#{@mm_level}"
    caller_line = caller.first.split(":")[1] if $DEBUG
    puts "#{__FILE__} : #{caller_line} : #{name}"   if $DEBUG


  end

  def to_hash
    { :class => self.class.to_s,
      :question => "is something missing?"
    }
  end

end


require "interscript/node/group"
require "interscript/node/document"
require "interscript/node/meta"
require "interscript/node/stage"
require "interscript/node/rule"
require "interscript/node/item"
