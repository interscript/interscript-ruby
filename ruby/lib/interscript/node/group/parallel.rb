class Interscript::Node::Group::Parallel < Interscript::Node::Group
  # A place for Interpreter to store a compiled form of the tree
  attr_accessor :cached_tree
  attr_accessor :subs_regexp, :subs_replacements, :subs_array

  def inspect
    "parallel {\n#{super}\n}"
  end
end
