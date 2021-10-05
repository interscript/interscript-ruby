module Interscript::DSL::SymbolMM
  def method_missing sym, *args, **kwargs, &block
    super if args.length > 0
    super if kwargs.length > 0
    super if sym.to_s =~ /[?!=]\z/
    super unless sym.to_s =~ /\A[\w\d]+\z/
    super if block_given?

    sym.to_sym
  end
end
