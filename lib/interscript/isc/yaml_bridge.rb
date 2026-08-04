# frozen_string_literal: true

require "lutaml/model"
require "interscript/isc/model"
require "interscript/isc/items"

module Interscript
  module Isc
    # Bridges the ISC document hash (from DocumentBuilder) and lutaml-model
    # objects for YAML serialization.
    #
    #   yaml_str = YamlBridge.to_yaml(doc_hash)
    #   doc_hash = YamlBridge.from_yaml(yaml_str)
    #
    module YamlBridge
      class << self
        def to_yaml(doc_hash)
          hash_to_model(doc_hash).to_yaml
        end

        def from_yaml(yaml_str)
          model_to_hash(Model::Document.from_yaml(yaml_str))
        end

        private

        def hash_to_model(doc_hash)
          Model::Document.new(
            system_code: doc_hash[:systemCode],
            metadata: normalize_metadata(doc_hash[:metadata]),
            tests: (doc_hash[:tests] || []).map { |t| Model::Test.new(t.transform_keys(&:to_s)) },
            aliases: (doc_hash[:aliases] || []).map { |a| build_alias_model(a) },
            stages: (doc_hash[:stages] || []).map { |s| build_stage_model(s) },
            dependencies: (doc_hash[:dependencies] || []).map { |d| build_dependency_model(d) },
          )
        end

        def normalize_metadata(meta)
          return {} unless meta.is_a?(Hash)
          meta.transform_values do |v|
            case v
            when Array then v.map { |i| normalize_meta_value(i) }
            else normalize_meta_value(v)
            end
          end.transform_keys(&:to_s)
        end

        def normalize_meta_value(v)
          v.is_a?(Symbol) ? v.to_s : v
        end

        def build_alias_model(alias_hash)
          Model::Alias.new(
            name: alias_hash[:name],
            value: item_to_model(alias_hash[:value]),
          )
        end

        def build_stage_model(stage_hash)
          Model::Stage.new(
            name: stage_hash[:name],
            body: (stage_hash[:body] || []).map { |item| stage_item_to_model(item) },
          )
        end

        def build_dependency_model(dep_hash)
          Model::Dependency.new(
            target: dep_hash[:target],
            alias_name: dep_hash[:alias],
          )
        end

        def stage_item_to_model(item)
          attrs = { kind: item[:kind].to_s }
          case item[:kind]
          when :parallel, :sequence
            attrs[:rules] = item[:rules].map { |r| rule_to_model(r) }
          when :bare_rule
            attrs[:rule] = rule_to_model(item[:rule])
          when :run
            attrs[:dependency] = item[:dependency]
            attrs[:stage] = item[:stage]
          when :separate
            attrs[:separator] = item[:separator] ? item_to_model(item[:separator]) : nil
          when :string_case
            attrs[:op] = item[:op]
          end
          Model::StageItem.new(attrs.compact)
        end

        def rule_to_model(rule_hash)
          Model::Rule.new(
            from: item_to_model(rule_hash[:from]),
            to: item_to_model(rule_hash[:to]),
            constraints: (rule_hash[:constraints] || []).map { |c| constraint_to_model(c) },
          )
        end

        def constraint_to_model(constraint_hash)
          Model::Constraint.new(
            kind: constraint_hash[:kind]&.to_s,
            item: constraint_hash[:item] ? item_to_model(constraint_hash[:item]) : nil,
          )
        end

        # Convert an Items::* object to a Model::Item
        def item_to_model(item)
          return nil unless item

          case item
          when Items::StringValue
            Model::Item.new(type: "string", value: item.value)
          when Items::None
            Model::Item.new(type: "none")
          when Items::Primitive
            Model::Item.new(type: "primitive", name: item.name)
          when Items::Function
            Model::Item.new(type: "function", name: item.name)
          when Items::AliasRef
            Model::Item.new(type: "alias_ref", name: item.name)
          when Items::Capture
            Model::Item.new(type: "capture", index: item.index)
          when Items::CaptureGroup
            Model::Item.new(type: "capture_group", inner: item_to_model(item.inner))
          when Items::Maybe
            Model::Item.new(type: "maybe", inner: item_to_model(item.inner))
          when Items::Some
            Model::Item.new(type: "some", inner: item_to_model(item.inner))
          when Items::Range
            Model::Item.new(type: "range", lo: item.lo, hi: item.hi)
          when Items::Set
            Model::Item.new(type: "set", chars: item.chars)
          when Items::Concat
            Model::Item.new(type: "concat", parts: item.parts.map { |p| item_to_model(p) })
          else
            Model::Item.new(type: "unknown", value: item.to_s)
          end
        end

        # --- Reverse direction: model → document hash ---

        def model_to_hash(model)
          {
            schemaVersion: 1,
            systemCode: model.system_code,
            metadata: model_metadata_to_hash(model.metadata),
            tests: (model.tests || []).map { |t| { input: t.input || "", expected: t.expected || "", note: t.note }.compact },
            aliases: (model.aliases || []).map { |a| { name: a.name, value: model_to_item(a.value) } },
            stages: (model.stages || []).map { |s| stage_model_to_hash(s) },
            dependencies: (model.dependencies || []).map { |d| { target: d.target, alias: d.alias_name }.compact },
          }
        end

        def model_metadata_to_hash(meta)
          return {} unless meta.is_a?(Hash)
          meta.transform_keys(&:to_sym)
        end

        def stage_model_to_hash(stage_model)
          {
            name: stage_model.name,
            body: stage_model.body.map { |item| stage_item_model_to_hash(item) },
          }
        end

        def stage_item_model_to_hash(item)
          case item.kind
          when "parallel", "sequence"
            { kind: item.kind.to_sym, rules: item.rules.map { |r| rule_model_to_hash(r) } }
          when "bare_rule"
            { kind: :bare_rule, rule: rule_model_to_hash(item.rule) }
          when "run"
            { kind: :run, dependency: item.dependency, stage: item.stage }
          when "separate"
            { kind: :separate, separator: item.separator ? model_to_item(item.separator) : nil }
          when "compose"
            { kind: :compose }
          when "string_case"
            { kind: :string_case, op: item.op }
          else
            { kind: item.kind&.to_sym }
          end
        end

        def rule_model_to_hash(rule_model)
          {
            from: model_to_item(rule_model.from),
            to: model_to_item(rule_model.to),
            constraints: (rule_model.constraints || []).map { |c| constraint_model_to_hash(c) },
          }
        end

        def constraint_model_to_hash(constraint_model)
          {
            kind: constraint_model.kind&.to_sym,
            item: constraint_model.item ? model_to_item(constraint_model.item) : nil,
          }
        end

        # Convert a Model::Item back to an Items::* object
        def model_to_item(item_model)
          return nil unless item_model

          case item_model.type
          when "string"
            Items::StringValue.new(item_model.value || "")
          when "none"
            Items::None.new
          when "primitive"
            Items::Primitive.new(item_model.name)
          when "function"
            Items::Function.new(item_model.name)
          when "alias_ref"
            Items::AliasRef.new(item_model.name)
          when "capture"
            Items::Capture.new(item_model.index)
          when "capture_group"
            Items::CaptureGroup.new(model_to_item(item_model.inner))
          when "maybe"
            Items::Maybe.new(model_to_item(item_model.inner))
          when "some"
            Items::Some.new(model_to_item(item_model.inner))
          when "range"
            Items::Range.new(item_model.lo, item_model.hi)
          when "set"
            Items::Set.new(item_model.chars || [])
          when "concat"
            Items::Concat.new((item_model.parts || []).map { |p| model_to_item(p) })
          else
            Items::StringValue.new(item_model.value.to_s)
          end
        end
      end
    end
  end
end
