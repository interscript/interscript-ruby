# frozen_string_literal: true

module Interscript
  module Isc
    module Grammar
      module Concerns
        autoload :Primitives, "interscript/isc/grammar/concerns/primitives"
        autoload :Items, "interscript/isc/grammar/concerns/items"
        autoload :Metadata, "interscript/isc/grammar/concerns/metadata"
        autoload :Aliases, "interscript/isc/grammar/concerns/aliases"
        autoload :Tests, "interscript/isc/grammar/concerns/tests"
        autoload :Stages, "interscript/isc/grammar/concerns/stages"
        autoload :Dependencies, "interscript/isc/grammar/concerns/dependencies"
        autoload :System, "interscript/isc/grammar/concerns/system"
      end
    end
  end
end
