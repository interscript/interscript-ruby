module Interscript::DSL::Items
  def method_missing sym, *args, **kwargs, &block
    super if args.length > 0
    super if kwargs.length > 0
    super if sym.to_s =~ /[?!=]\z/
    super if block_given?

    Interscript::Node::Item::Alias.new(sym)
  end

  def any(*chars)
    puts "any(#{chars.inspect}) from #{self.inspect}" if $DEBUG
    Interscript::Node::Item::Any.new(*chars)
  end

  # Implementation of `map[:x]`
  def map; Interscript::DSL::Items::Maps; end

  # Implementation of `stage[:x]`
  def stage; Stages.new; end

  # Implementation of `map[:x]`
  module Maps
    # Select a remote map
    def self.[] map
      Symbol === map or raise TypeError, "A map name must be a Symbol, not #{alias_name.class}"
      Map.new(map)
    end
  end

  # Implementation of `map[:x][:alias]` and `map[:x].stage[:stage]`
  class Map
    def initialize name; @name = name; end

    # Implementation of `map[:x][:alias]`
    def [] alias_name
      Symbol === alias_name or raise TypeError, "An alias name must be a Symbol, not #{alias_name.class}"
      Interscript::Node::Item::Alias.new(alias_name, map: name)
    end

    # Implementation of `map[:x].stage[:stage]`
    def stage; Stages.new(@name); end
  end

  # Implementation of `map[:x].stage[:stage]` and `stage[:stage]`
  class Stages
    def initialize map=nil; @map = map; end

    def [] stage
      Interscript::Node::Item::Stage.new(stage, map: @map)
    end
  end
end
