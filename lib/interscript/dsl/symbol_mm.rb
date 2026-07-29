module Interscript::DSL::SymbolMM
  def method_missing sym, *args, **kwargs, &block
    super if args.length > 0
    super if kwargs.length > 0
    super if /[?!=]\z/.match?(sym.to_s)
    super unless /\A[\w\d]+\z/.match?(sym.to_s)
    super if block_given?

    sym.to_sym
  end
end
