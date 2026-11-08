# frozen_string_literal: true

require "lutaml/model"
require "interscript/isc/model/item"
require "interscript/isc/model/constraint"

module Interscript
  module Isc
    module Model
      class Rule < Lutaml::Model::Serializable
        attribute :from, Item
        attribute :to, Item
        attribute :constraints, Constraint, collection: true
        attribute :when_languages, :string, collection: true

        yaml do
          map "from", to: :from
          map "to", to: :to
          map "constraints", to: :constraints
          map "when_languages", to: :when_languages
        end
      end
    end
  end
end
