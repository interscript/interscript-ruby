module Interscript::DSL::Items
  # Those are for the stdlib and we don't need those as we have a method_missing
  #
  #%i{boundary not_word line_start line_end none space}.each do |sym|
  #  define_method sym do
  #    Interscript::Node::Item::Alias.new(sym)
  #  end
  #end

  def method_missing sym, *args, **kwargs
    super if args.length > 0
    super if kwargs.length > 0
    super if sym.to_s =~ /[?!=]\z/

    Interscript::Node::Item::Alias.new(sym)
  end

  def any(*chars)
    puts "any(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::Any.new(*chars)
  end
end
