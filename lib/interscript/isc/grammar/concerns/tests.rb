# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Tests block: normative input/output pairs.
        module Tests
          include Parslet

          rule(:tests_block) do
            str("tests") >> whitespace? >>
              braced(test_line.repeat(0)).as(:tests)
          end

          rule(:test_line) do
            whitespace? >>
              quoted_string.as(:input) >>
              arrow >>
              quoted_string.as(:expected) >>
              (whitespace >> str("note") >> whitespace >>
                quoted_string.as(:note)).maybe >>
              whitespace?
          end
        end
      end
    end
  end
end
