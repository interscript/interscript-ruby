class Interscript::Stdlib
  ALIASES = {
    none: "",
    space: " ",
    whitespace: "[\\b \\t\\0\\r\\n]",
    boundary: "\\b",
    word: "\\w",
    not_word: "\\W",
    alpha: "[a-zA-Z]",
    not_alpha: "[^a-zA-Z]",
    digit: "\\d",
    not_digit: "\\D",
    line_start: "^",
    line_end: "$",
    string_start: "\\A",
    string_end: "\\z"
  }

  def self.re_only_alias?(a)
    ! %i[none space].include?(a)
  end
end
