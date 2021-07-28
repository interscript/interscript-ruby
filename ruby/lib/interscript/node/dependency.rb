class Interscript::Node::Dependency < Interscript::Node
  attr_accessor :name, :full_name, :import, :document

  def initialize
  end

  def reverse
    rdep = self.class.new
    rdep.name = name
    rdep.full_name = Interscript::Node::Document.reverse_name(full_name)
    rdep.import = import
    rdep.document = document&.reverse
    rdep
  end

  def to_hash
    { :class => self.class.to_s,
      :name => @name,
      :full_name => @full_name,
      :import => @import }
  end
end
