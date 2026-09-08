module Interscript::DSL::SymbolMM
  # standard:disable Style/MissingRespondToMissing (DSL method_missing catches unknown method names by design)
  def method_missing sym, *args, **kwargs, &block
    # standard:enable Style/MissingRespondToMissing
    super if args.length > 0
    super if kwargs.length > 0
    super if /[?!=]\z/.match?(sym.to_s)
    super unless /\A[\w\d]+\z/.match?(sym.to_s)
    super if block_given?

    sym.to_sym
  end
end
