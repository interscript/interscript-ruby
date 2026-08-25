# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Aliases block: named expressions reused throughout the system.
        module Aliases
          include Parslet

          rule(:aliases_block) do
            str("aliases") >> whitespace? >>
              braced(alias_decl.repeat(0)).as(:aliases)
          end

          rule(:alias_decl) do
            whitespace? >>
              identifier.as(:name) >> whitespace? >>
              str("=") >> whitespace? >>
              item.as(:value) >>
              whitespace?
          end
        end
      end
    end
  end
end
