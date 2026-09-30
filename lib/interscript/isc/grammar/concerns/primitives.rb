# frozen_string_literal: true

require "parsanol"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Lexical primitives shared by every other concern.
        # Mirrors the structure of LutaML LML's Concerns::Primitives.
        module Primitives
          include Parsanol

          # -- Whitespace and comments

          rule(:space) { match(/\s/).repeat(1) }
          rule(:space?) { space.maybe }

          rule(:newline) { str("\n") | str("\r\n") | str("\r") }
          rule(:newlines) { newline.repeat(1) }
          rule(:newlines?) { newlines.maybe }

          rule(:line_comment) do
            str("#") >> (newline.absent? >> any).repeat
          end

          rule(:whitespace) do
            (space | line_comment).repeat(1)
          end
          rule(:whitespace?) { whitespace.maybe }

          # Inline whitespace: spaces and tabs only, NO newlines. Used between
          # a field name and its value to prevent eating the newline that
          # signals an empty value.
          rule(:inline_space) { match(/[ \t]/).repeat(1) }
          rule(:inline_whitespace) do
            (inline_space | line_comment).repeat(1)
          end
          rule(:inline_whitespace?) { inline_whitespace.maybe }

          # Comma, used in lists. Trailing whitespace allowed.
          rule(:comma) { str(",") >> whitespace? }

          # Arrow, used in tests.
          rule(:arrow) { whitespace? >> str("->") >> whitespace? }

          # -- Identifiers

          rule(:identifier_first) { match(/[a-zA-Z_]/) }
          rule(:identifier_rest) { match(/[a-zA-Z0-9_]/) }
          rule(:identifier) do
            (identifier_first >> identifier_rest.repeat).as(:identifier)
          end

          # -- String literals

          rule(:escape_sequence) do
            str("\\") >> (
              str("n").as(:newline) |
              str("r").as(:carriage_return) |
              str("t").as(:tab) |
              str('"').as(:dquote) |
              str("\\").as(:backslash) |
              (str("u") >> match(/[0-9a-fA-F]/).repeat(4, 4).as(:unicode)) |
              (str("U") >> match(/[0-9a-fA-F]/).repeat(8, 8).as(:unicode))
            )
          end

          # Single-quoted strings: no escape interpretation.
          rule(:single_quoted_string) do
            str("'") >>
              (str("'").absent? >> any).repeat.as(:string) >>
              str("'")
          end

          # Double-quoted strings: \\uXXXX, \\n, etc. are interpreted.
          # Escape-free stretches are captured as ONE run slice — a
          # per-char capture allocates a hash + slice per character
          # (~700k nodes for a large map) and the Transform pattern
          # match grinds on them even under the native parse engine.
          rule(:plain_run) do
            (str("\\") | str('"')).absent? >> any
          end
          rule(:double_quoted_string) do
            str('"') >>
              (escape_sequence | plain_run.repeat(1).as(:run)).repeat.as(:string) >>
              str('"')
          end

          rule(:quoted_string) do
            double_quoted_string | single_quoted_string
          end

          # -- Brace-delimited block scaffold

          # Wrap an inner rule in `{ ... }` with optional surrounding whitespace.
          def braced(inner)
            str("{") >> whitespace? >>
              inner >>
              whitespace? >> str("}")
          end
        end
      end
    end
  end
end
