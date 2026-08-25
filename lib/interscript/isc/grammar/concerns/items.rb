# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Item expressions: the building blocks of rule matches and targets.
        module Items
          include Parslet

          rule(:item_atom) do
            quoted_string |
              str("none").as(:none) |
              zero_width_primitive |
              any_character |
              any_constructor |
              capture_constructor |
              maybe_constructor |
              some_constructor |
              function_call |
              capture_reference |
              alias_reference
          end

          # some(...) — one or more matches (greedy).
          rule(:some_constructor) do
            str("some") >> str("(") >> whitespace? >>
              item.as(:some_inner) >>
              whitespace? >> str(")")
          end

          # Function call: upcase, downcase, title_case, reverse, etc.
          # These appear as the `to` value in sub rules: `sub "X" upcase`.
          rule(:function_call) do
            (str("upcase") | str("downcase") | str("title_case") |
              str("reverse") | str("strip") | str("swapcase")).as(:function)
          end

          rule(:zero_width_primitive) do
            (
              str("boundary") |
              str("line_start") |
              str("line_end") |
              str("word_boundary") |
              str("space") |
              str("non_boundary")
            ).as(:primitive)
          end

          # any_character — matches any single character.
          rule(:any_character) do
            str("any_character").as(:any_char)
          end

          rule(:any_constructor) do
            str("any") >> str("(") >> whitespace? >>
              (range_arg | set_arg | alias_arg | item.as(:any_item)).as(:any) >>
              whitespace? >> str(")")
          end

          # `any(identifier)` — accept a bare alias reference inside any().
          # Exclude zero-width primitives (space, boundary, etc.) which are
          # handled by `item` via `zero_width_primitive` in `item_atom`.
          rule(:alias_arg) do
            (zero_width_primitive.absent? >> keyword.absent? >> identifier).as(:alias_ref)
          end

          # capture(...) — wraps a sub-expression with a capture group.
          # The captured value can be referenced in the target via `ref(N)`.
          rule(:capture_constructor) do
            str("capture") >> str("(") >> whitespace? >>
              item.as(:capture_inner) >>
              whitespace? >> str(")")
          end

          # maybe(...) — optional match (zero or one occurrence).
          rule(:maybe_constructor) do
            str("maybe") >> str("(") >> whitespace? >>
              item.as(:maybe_inner) >>
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
                (list_item >> ((comma | whitespace) >> list_item).repeat).as(:list) >>
                whitespace? >> str("]"))
          end

          # A list item is an item expression (which includes quoted strings).
          rule(:list_item) do
            item
          end

          rule(:alias_reference) do
            (keyword.absent? >> identifier >> str("{").absent?).as(:alias)
          end

          # ref(N) — reference to Nth capture group. Only valid in `to` position.
          rule(:capture_reference) do
            (str("ref") >> str("(") >> whitespace? >>
              match(/[0-9]/).as(:digit) >> whitespace? >>
              str(")")).as(:ref)
          end

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
              str("downcase") | str("upcase") | str("title_case") |
              str("capture") | str("maybe") | str("some") | str("ref") |
              str("any_character")
          end

          # Concatenation: one or more atoms. The continuation pattern
          # requires that whitespace or `+` be IMMEDIATELY followed by
          # something that's clearly an item_atom start (a quote, `(`,
          # letter, etc.) AND not a block-rule keyword like `to`, `before`.
          rule(:item) do
            (item_atom >>
              ((concat_sep >> item_continuation.present?) >> item_atom).repeat
            ).as(:concatenation)
          end

          rule(:concat_sep) do
            (whitespace? >> str("+") >> whitespace?) | whitespace
          end

          # Positive lookahead: the next thing is a valid item_atom continuation.
          # Excludes keywords that end the item (to, before, after, not_before,
          # not_after, the closing brace, AND `identifier =` which signals a
          # new alias declaration).
          rule(:item_continuation) do
            (str("to") | str("before") | str("after") |
              str("not_before") | str("not_after") |
              str("}")).absent? >>
              (identifier >> whitespace? >> str("=")).absent? >>
              item_atom_start
          end

          rule(:item_atom_start) do
            str('"') | str("'") |
              match(/[A-Za-z_]/)
          end

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
