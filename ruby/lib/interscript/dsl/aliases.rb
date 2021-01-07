class Interscript::DSL::Aliases
  include Interscript::DSL::Items

  attr_accessor :node

  def initialize(&block)
    @node = {}
    self.instance_exec(&block)
  end

  def def_alias(name, value)
    if Interscript::Node::Item::Alias === name
      name = name.name
    end

    unless Symbol === name
      raise TypeError, "Alias name must be a Symbol, given #{name.class}"
    end

    puts "def_alias(#{name.inspect}, #{thing.inspect})" if $DEBUG
    @node[name] = Interscript::Node::AliasDef.new(name, value)
  end
end
