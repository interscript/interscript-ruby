# frozen_string_literal: true

require "lutaml/model"

module Interscript
  module Isc
    module Model
      class Dependency < Lutaml::Model::Serializable
        attribute :target, :string
        attribute :alias_name, :string

        yaml do
          map "target", to: :target
          map "alias", to: :alias_name
        end
      end
    end
  end
end
