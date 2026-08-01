# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Item expressions: the building blocks of rule matches and targets.
        module Items
          include Parslet

          # An item atom is one of:
          #   * quoted string literal
          #   * keyword none (empty match)
          #   * zero-width primitive (boundary, line_start, etc.)
          #   * any(...) constructor — range or set
          #   * bare identifier — alias reference
          #   * capture reference \N (valid in target only; parser accepts everywhere
          #     and semantic layer enforces target-only)
          rule(:item_atom) do
            quoted_string |
              str("none").as(:none) |
              zero_width_primitive |
              any_constructor |
              capture_reference |
              alias_reference
          end

          rule(:zero_width_primitive) do
            (
              str("boundary") |
              str("line_start") |
              str("line_end") |
              str("word_boundary")
            ).as(:primitive)
          end

          rule(:any_constructor) do
            str("any") >> str("(") >> whitespace? >>
              (range_arg | set_arg).as(:any) >>
              whitespace? >> str(")")
          end

          rule(:range_arg) do
            quoted_string.as(:lo) >>
              whitespace? >> str("..") >> whitespace? >>
              quoted_string.as(:hi)
          end

          rule(:set_arg) do
            quoted_string.as(:single) |
              (str("[") >> whitespace? >>
                (quoted_string >> (whitespace >> quoted_string).repeat).as(:list) >>
                whitespace? >> str("]"))
          end

          rule(:alias_reference) do
            # An alias reference is an identifier that isn't a reserved keyword
            # AND isn't immediately followed by `{` (which would make it a
            # block opener like `parallel {`).
            (keyword.absent? >> identifier >> str("{").absent?).as(:alias)
          end

          # Reserved keywords that should never be parsed as alias references.
          rule(:keyword) do
            str("parallel") | str("sequence") | str("stage") |
              str("compose") | str("separate") | str("system") |
              str("metadata") | str("aliases") | str("tests") |
              str("notes") | str("description") | str("name") |
              str("authority") | str("dependency") | str("run") |
              str("sub") | str("before") | str("after") |
              str("not_before") | str("not_after") | str("any") |
              str("none") | str("boundary") | str("line_start") |
              str("line_end") | str("word_boundary") |
              str("downcase") | str("upcase") | str("title_case")
          end

          rule(:capture_reference) do
            (str("\\") >> match(/[0-9]/).as(:digit)).as(:capture)
          end

          # Concatenation: two or more adjacent atoms (whitespace-separated).
          # A single atom is also accepted (degenerate concatenation).
          rule(:item) do
            (item_atom >> (whitespace >> item_atom).repeat).as(:concatenation)
          end

          # Constraint clauses attached to a rule.
          rule(:constraint) do
            (
              (str("before")     >> whitespace >> item.as(:before)) |
              (str("after")      >> whitespace >> item.as(:after)) |
              (str("not_before") >> whitespace >> item.as(:not_before)) |
              (str("not_after")  >> whitespace >> item.as(:not_after))
            )
          end

          rule(:constraints) do
            (whitespace >> constraint).repeat.as(:constraints)
          end
        end
      end
    end
  end
end
