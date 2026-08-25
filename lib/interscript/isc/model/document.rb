# frozen_string_literal: true

require "lutaml/model"
require "interscript/isc/model/test"
require "interscript/isc/model/alias"
require "interscript/isc/model/stage"
require "interscript/isc/model/dependency"

module Interscript
  module Isc
    module Model
      class Document < Lutaml::Model::Serializable
        attribute :system_code, :string
        attribute :metadata, :hash
        attribute :tests, Test, collection: true
        attribute :aliases, Alias, collection: true
        attribute :stages, Stage, collection: true
        attribute :dependencies, Dependency, collection: true

        yaml do
          map "system_code", to: :system_code
          map "metadata", to: :metadata
          map "tests", to: :tests
          map "aliases", to: :aliases
          map "stages", to: :stages
          map "dependencies", to: :dependencies
        end
      end
    end
  end
end
