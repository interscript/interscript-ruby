# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Top-level system block.
        module System
          include Parslet

          # A block-item is any of the top-level constructs that may appear
          # inside `system "<code>" { ... }`.
          rule(:block_item) do
            whitespace? >>
              (metadata_block | aliases_block | tests_block |
                stage_block | dependency_decl) >>
              whitespace?
          end

          rule(:system_block) do
            str("system") >> whitespace >>
              quoted_string.as(:system_code) >> whitespace? >>
              braced(block_item.repeat(0)).as(:body) >>
              whitespace?
          end

          # Root rule.
          rule(:isc_source) do
            whitespace? >> system_block.as(:system) >> whitespace?
          end
        end
      end
    end
  end
end
