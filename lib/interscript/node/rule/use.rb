class Interscript::Node::Rule::Use < Interscript::Node::Rule
  # ISC-WF-1 W1/W2: a `use` directive before expansion. The NodeAdapter
  # expands use directives at build time (macro expansion, spec §3.2), so
  # this node only appears on documents built without expansion; it names
  # the ruleset and, when present, the dependency alias and the per-site
  # override rows.
  attr_accessor :ruleset, :map, :overrides

  def initialize(ruleset, map: nil, overrides: [])
    self.ruleset = ruleset
    self.map = map
    self.overrides = overrides
  end

  def to_hash
    {class: self.class.to_s,
     ruleset: ruleset,
     map: map,
     overrides: overrides.map(&:to_hash)}
  end

  def ==(other)
    super && ruleset == other.ruleset && map == other.map && overrides == other.overrides
  end

  def inspect
    out = "use #{[map, ruleset].compact.map { |i| "@#{i}" }.join(".")}"
    out += " override { #{overrides.map(&:inspect).join(", ")} }" unless overrides.empty?
    out
  end
end
