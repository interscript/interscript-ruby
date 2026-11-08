class Interscript::Node::LanguagesDecl < Interscript::Node
  # ISC-WF-1 W3: the languages a map serves (spec §5.1). Attached to
  # Node::Document#languages; nil means "no declaration" — every `when`
  # guard is inert regardless of caller selection.
  attr_accessor :languages

  def initialize(languages = [])
    self.languages = languages
  end

  def include?(language)
    languages.include?(language)
  end

  def to_hash
    {class: self.class.to_s, languages: languages}
  end

  def ==(other)
    super && languages == other.languages
  end

  def inspect
    "languages #{languages.join(" ")}"
  end
end
