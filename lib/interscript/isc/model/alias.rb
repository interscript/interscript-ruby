# frozen_string_literal: true

require "lutaml/model"
require "interscript/isc/model/item"

module Interscript
  module Isc
    module Model
      class Alias < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :value, Item

        yaml do
          map "name", to: :name
          map "value", to: :value
        end
      end
    end
  end
end
