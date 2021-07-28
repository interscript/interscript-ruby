class Interscript::Node::Document
  attr_accessor :metadata, :tests, :name
  attr_accessor :dependencies, :aliases, :stages, :dep_aliases

  def initialize
    puts "Interscript::Node::Document.new " if $DEBUG
    @metadata = nil
    @tests = nil
    @dependencies = []
    @dep_aliases = {}
    @aliases = {}
    @stages = {}
  end

  def imported_aliases
    aliases = @aliases
    @dependencies.select(&:import).each do |d|
      aliases = d.document.aliases.merge(aliases)
    end
    aliases
  end

  def imported_stages
    stages = @stages
    @dependencies.select(&:import).each do |d|
      stages = d.document.stages.merge(stages)
    end
    stages
  end

  def all_dependencies
    (dependencies + dependencies.map { |i| i.document.dependencies }).flatten.uniq_by do |i|
      i.full_name
    end
  end

  def reverse
    @reverse ||= self.class.new.tap do |rdoc|
      rdoc.name = self.class.reverse_name(name)
      rdoc.metadata = metadata&.reverse
      rdoc.tests = tests&.reverse
      rdoc.dependencies = dependencies.map(&:reverse)
      rdoc.stages = stages.transform_values(&:reverse)
      rdoc.dep_aliases = dep_aliases.transform_values(&:reverse)
      rdoc.aliases = aliases
    end
  end

  def self.reverse_name(name)
    newname = (name || "noname").split("-")
    newname[2], newname[3] = newname[3], newname[2] if newname.length >= 4
    newname = newname.join("-")
    if newname == name
      newname.gsub!("-reverse", "")
    end
    if newname == name
      newname += "-reverse"
    end
    newname
  end

  def to_hash
    { :class => self.class.to_s, :metadata => @metadata&.to_hash,
      :tests => @tests&.to_hash,
      :dependencies => @dependencies.map{|x| x.to_hash},
      :dep_aliases => @dep_aliases.transform_values(&:to_hash),
      :aliases => @aliases.transform_values(&:to_hash),
      :stages => @stages.transform_values(&:to_hash) }
  end
end
