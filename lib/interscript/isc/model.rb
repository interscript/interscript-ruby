# frozen_string_literal: true

require "lutaml/model"

module Interscript
  module Isc
    module Model
      autoload :Item, "interscript/isc/model/item"
      autoload :Constraint, "interscript/isc/model/constraint"
      autoload :Rule, "interscript/isc/model/rule"
      autoload :StageItem, "interscript/isc/model/stage_item"
      autoload :Stage, "interscript/isc/model/stage"
      autoload :Alias, "interscript/isc/model/alias"
      autoload :Test, "interscript/isc/model/test"
      autoload :Dependency, "interscript/isc/model/dependency"
      autoload :Document, "interscript/isc/model/document"
    end
  end
end
