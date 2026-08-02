# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Metadata block: identity + provenance + lifecycle of a system.
        module Metadata
          include Parslet

          rule(:metadata_block) do
            str("metadata") >> whitespace? >>
              braced(metadata_field.repeat(0)).as(:metadata)
          end

          rule(:metadata_field) do
            whitespace? >>
              (
                description_field |
                relations_field |
                system_status_field |
                code_status_field |
                specification_field |
                notes_field |
                provenance_field |
                generic_field
              ) >> whitespace?
          end

          rule(:authority_field) do
            str("authority") >> whitespace >> quoted_string.as(:authority)
          end

          rule(:source_spelling_field) do
            str("source_spelling") >> whitespace >> quoted_string.as(:source_spelling)
          end

          rule(:target_spelling_field) do
            str("target_spelling") >> whitespace >> quoted_string.as(:target_spelling)
          end

          rule(:identifying_field) do
            str("identifying") >> whitespace >> quoted_string.as(:identifying)
          end

          rule(:name_field) do
            str("name") >> whitespace >> quoted_string.as(:name)
          end

          rule(:specification_field) do
            str("specification") >> whitespace >>
              quoted_string.as(:specification) >>
              (comma >> quoted_string.as(:specification)).repeat
          end

          rule(:description_field) do
            str("description") >> whitespace? >>
              braced(raw_text.as(:description))
          end

          rule(:system_status_field) do
            str("system_status") >> whitespace >>
              (str("current") | str("former") | str("inactive")).as(:system_status)
          end

          rule(:code_status_field) do
            str("code_status") >> whitespace >>
              (str("preferred") | str("proposed") | str("deprecated")).as(:code_status)
          end

          rule(:relations_field) do
            str("relations") >> whitespace? >>
              braced(relation_block.repeat(0)).as(:relations)
          end

          rule(:relation_block) do
            whitespace? >>
              relation_type.as(:type) >> whitespace >>
              quoted_string.as(:system) >>
              (whitespace >> str("note") >> whitespace >>
                quoted_string.as(:note)).maybe >>
              whitespace?
          end

          rule(:relation_type) do
            str("supersedes") | str("superseded_by") | str("based_on") |
              str("basis_for") | str("alias_of") | str("adopted_from") |
              str("related_to")
          end

          rule(:notes_field) do
            str("notes") >> whitespace? >>
              braced(note_line.repeat(0)).as(:notes)
          end

          rule(:note_line) do
            whitespace? >>
              str("note") >> whitespace? >>
              quoted_string.as(:note) >> whitespace?
          end

          rule(:provenance_field) do
            str("provenance") >> whitespace? >>
              quoted_string.as(:provenance) >>
              (comma >> quoted_string.as(:provenance)).repeat
          end

          # Generic field: any identifier followed by a bare value (string,
          # number, or whitespace-delimited tokens up to the next field or
          # close brace). This makes the parser permissive about future
          # field additions; semantic validation happens in DocumentBuilder.
          rule(:generic_field) do
            identifier.as(:field_name) >> inline_whitespace? >>
              (empty_field |
               field_value.as(:field_value) |
               braced(raw_text.as(:field_block)))
          end

          rule(:field_value) do
            quoted_string |
              (newline.absent? >> (str("}").absent? >> str("{").absent? >> any)).repeat(1).as(:raw)
          end

          rule(:empty_field) do
            # An identifier with no value (just newline or `}` after). Use
            # lookahead without consuming.
            (newline.present? | str("}").present?)
          end

          # Raw text inside `{ ... }` — for description blocks. Consumes any
          # character that isn't an unescaped closing brace. Literal braces
          # inside the body are escaped as `\{` and `\}` by the codemod.
          rule(:raw_text) do
            (str("\\{") | str("\\}") | (str("}").absent? >> any)).repeat
          end
        end
      end
    end
  end
end
