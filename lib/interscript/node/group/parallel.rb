class Interscript::Node::Group::Parallel < Interscript::Node::Group
  # A place for Interpreter to store a compiled form of the tree
  attr_accessor :cached_tree
  attr_accessor :subs_regexp, :subs_replacements, :subs_array
  # ISC-WF-1 W3: per-selected-language filtered variants of this pass
  # (selected language => parallel group). Only populated for passes
  # that contain `when`-guarded rules.
  attr_accessor :wf1_variants

  def inspect
    "parallel {\n#{super}\n}"
  end
end
