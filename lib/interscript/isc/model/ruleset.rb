# frozen_string_literal: true

require "lutaml/model"
require "interscript/isc/model/stage_item"

module Interscript
  module Isc
    module Model
      # ISC-WF-1 W1: a named, reusable block of stage items (spec §3).
      class Ruleset < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :body, StageItem, collection: true

        yaml do
          map "name", to: :name
          map "body", to: :body
        end
      end
    end
  end
end
