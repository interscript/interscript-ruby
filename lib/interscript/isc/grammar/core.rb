# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    module Grammar
      # Core grammar: composes every concern into a single Parser ancestor.
      # Mirrors the structure of LutaML LML's Grammar::Core.
      module Core
        include Parslet
        include Concerns::Primitives
        include Concerns::Items
        include Concerns::Metadata
        include Concerns::Aliases
        include Concerns::Tests
        include Concerns::Stages
        include Concerns::Dependencies
        include Concerns::System
      end
    end
  end
end
