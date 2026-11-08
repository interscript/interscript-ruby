# frozen_string_literal: true

require "lutaml/model"
require "interscript/isc/model/rule"
require "interscript/isc/model/item"

module Interscript
  module Isc
    module Model
      # A single item in a stage body. Discriminated by `kind`:
      #   parallel, sequence, bare_rule, run, use, separate, compose,
      #   string_case
      class StageItem < Lutaml::Model::Serializable
        attribute :kind, :string
        attribute :rules, Rule, collection: true
        attribute :rule, Rule
        attribute :dependency, :string
        attribute :stage, :string
        attribute :separator, Item
        attribute :op, :string
        # ISC-WF-1 W1/W2: the referenced ruleset and the per-site
        # override rows; `dependency` carries the alias for qualified
        # references (`use alias.<ruleset>`).
        attribute :ruleset, :string
        attribute :overrides, Rule, collection: true

        yaml do
          map "kind", to: :kind
          map "rules", to: :rules
          map "rule", to: :rule
          map "dependency", to: :dependency
          map "stage", to: :stage
          map "separator", to: :separator
          map "op", to: :op
          map "ruleset", to: :ruleset
          map "overrides", to: :overrides
        end
      end
    end
  end
end
