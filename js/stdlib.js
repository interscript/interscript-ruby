var is_stdlib_aliases = {
  none: "",
  space: " ",
  whitespace: "[\b \t\0\r\n]",
  boundary: "\b",
  word: "\w",
  not_word: "\W",
  alpha: "[a-zA-Z]",
  not_alpha: "[^a-zA-Z]",
  digit: "\d",
  not_digit: "\D",
  line_start: "^", // JS has no robust new line regexp handling
  line_end: "$", // JS has no robust new line regexp handling
  string_start: "^",
  string_end: "$"
}
