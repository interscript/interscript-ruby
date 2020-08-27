def translate_regexp(src)
  src.
    gsub('[:upper:]', '\\\\\\\\p{Lu}').
    gsub('[:lower:]', '\\\\\\\\p{Ll}').
    gsub('[:alpha:]', '\\\\\\\\p{L}').
    gsub('(?<=[\\\\p{Lu}])?', '(?<=[\\\\\\\\p{Lu}]?)').
    gsub('(?=[\\\\p{Lu}])?', '(?=[\\\\\\\\p{Lu}]?)')
end
