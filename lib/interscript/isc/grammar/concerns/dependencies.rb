# frozen_string_literal: true

require "parsanol"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Dependencies: references to other systems whose stages may be invoked.
        module Dependencies
          include Parsanol

          rule(:dependency_decl) do
            str("dependency") >> whitespace >>
              quoted_string.as(:target) >>
              (whitespace >> str("as") >> whitespace >>
                identifier.as(:alias)).maybe
          end
        end
      end
    end
  end
end
