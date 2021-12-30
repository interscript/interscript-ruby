module Interscript::DSL::Items
  include Interscript::DSL::SymbolMM

  def method_missing sym, *args, **kwargs, &block
    super if args.length > 0
    super if kwargs.length > 0
    super if sym.to_s =~ /[?!=]\z/
    super unless sym.to_s =~ /\A[\w\d]+\z/
    super if block_given?

    Interscript::Node::Item::Alias.new(sym)
  end

  def any(*chars)
    puts "any(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::Any.new(*chars)
  end

  # a?
  def maybe(*chars)
    puts "maybe(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::Maybe.new(*chars)
  end

  def maybe_some(*chars)
    puts "maybe_some(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::MaybeSome.new(*chars)
  end

  def some(*chars)
    puts "some(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::Some.new(*chars)
  end

  # (...)
  def capture(expr)
    puts "capture(#{expr.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::CaptureGroup.new(expr)
  end

  # \1
  def ref(int)
    puts "ref(#{int.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::CaptureRef.new(int)
  end

  # Implementation of `map.x`
  def map; Interscript::DSL::Items::Maps; end

  # Implementation of `stage.x`
  def stage; Stages.new; end

  # Implementation of `map.x`
  module Maps
    class << self
      # Select a remote map
      def [] map
        Symbol === map or raise Interscript::MapLogicError, "A map name must be a Symbol, not #{alias_name.class}"
        Map.new(map)
      end
      alias method_missing []
    end
  end

  # Implementation of `map.x.aliasname` and `map.x.stage.stagename`
  class Map
    def initialize name; @name = name; end

    # Implementation of `map.x.aliasname`
    def [] alias_name
      Symbol === alias_name or raise Interscript::MapLogicError, "An alias name must be a Symbol, not #{alias_name.class}"
      Interscript::Node::Item::Alias.new(alias_name, map: @name)
    end
    alias method_missing []

    # Implementation of `map.x.stage.stagename`
    def stage; Stages.new(@name); end
  end

  # Implementation of `map.x.stage.stagename` and `stage.stagename`
  class Stages
    def initialize map=nil; @map = map; end

    def [] stage
      Interscript::Node::Item::Stage.new(stage, map: @map)
    end
    alias method_missing []
  end
end
