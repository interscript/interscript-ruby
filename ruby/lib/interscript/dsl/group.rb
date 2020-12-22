module Interscript::DSL::Group

  %i{boundary not_word line_start line_end none space}.each do |sym|
    self.send(:define_method,sym) {
       Interscript::Node::Item.new(sym)}
  end


  # method doubled in stage.rb
  def sub(from, to, **kargs, &block)
    puts "sub(#{from.inspect},#{to}, kargs = #{
      kargs.inspect
    }) from #{self.inspect}" if $DEBUG

    self.children << Interscript::Node::Rule::Sub.new(from,to,**kargs)
  end

  def any(chars)
    puts "any(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::Any.new(chars)
  end
  
end