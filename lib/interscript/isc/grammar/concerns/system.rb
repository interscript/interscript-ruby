# frozen_string_literal: true

require "parsanol"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Top-level system block.
        module System
          include Parsanol

          # ISC-WF-1 W3: the languages a map serves, declared once per map
          # inside the system block alongside metadata (spec §5.1). List
          # identifiers are keyword-guarded so the repeat stops at the next
          # block item (`stage`, `ruleset`, …) instead of swallowing it.
          rule(:languages_decl) do
            str("languages") >> whitespace >>
              (keyword.absent? >> identifier.as(:language) >>
                ((comma | whitespace) >> (keyword.absent? >> identifier.as(:language))).repeat
              ).as(:languages)
          end

          # A block-item is any of the top-level constructs that may appear
          # inside `system "<code>" { ... }`.
          rule(:block_item) do
            whitespace? >>
              (metadata_block | aliases_block | tests_block | languages_decl |
                ruleset_block | stage_block | dependency_decl) >>
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
