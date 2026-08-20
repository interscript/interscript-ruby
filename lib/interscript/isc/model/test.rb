# frozen_string_literal: true

require "lutaml/model"

module Interscript
  module Isc
    module Model
      class Test < Lutaml::Model::Serializable
        attribute :input, :string
        attribute :expected, :string
        attribute :note, :string

        yaml do
          map "input", to: :input
          map "expected", to: :expected
          map "note", to: :note
        end
      end
    end
  end
end
