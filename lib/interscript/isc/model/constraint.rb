# frozen_string_literal: true

require "lutaml/model"
require "interscript/isc/model/item"

module Interscript
  module Isc
    module Model
      class Constraint < Lutaml::Model::Serializable
        attribute :kind, :string
        attribute :item, Item

        yaml do
          map "kind", to: :kind
          map "item", to: :item
        end
      end
    end
  end
end
