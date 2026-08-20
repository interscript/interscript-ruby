# frozen_string_literal: true

require "lutaml/model"
require "interscript/isc/model"

module Interscript
  module Isc
    module Model
      # Polymorphic representation of an ISC item (StringValue, AliasRef, etc.)
      # Serialized as a discriminated union keyed by the `type` field.
      #
      # YAML shape:
      #   type: string
      #   value: "hello"
      #   ---
      #   type: alias_ref
      #   name: my_alias
      #   ---
      #   type: concat
      #   parts:
      #     - type: string
      #       value: "a"
      #     - type: alias_ref
      #       name: consonants
      class Item < Lutaml::Model::Serializable
        attribute :type, :string
        attribute :value, :string
        attribute :name, :string
        attribute :index, :integer
        attribute :lo, :string
        attribute :hi, :string
        attribute :chars, :string, collection: true
        attribute :parts, Item, collection: true
        attribute :inner, Item

        yaml do
          map "type", to: :type
          map "value", to: :value
          map "name", to: :name
          map "index", to: :index
          map "lo", to: :lo
          map "hi", to: :hi
          map "chars", to: :chars
          map "parts", to: :parts
          map "inner", to: :inner
        end
      end
    end
  end
end
