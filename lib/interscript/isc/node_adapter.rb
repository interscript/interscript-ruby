# frozen_string_literal: true

module Interscript
  module Isc
    # Bridges the ISC document hash (from DocumentBuilder) to the existing
    # Interscript::Node::Document object model, enabling .isc files to be
    # used for actual transliteration via the standard runtime.
    #
    # This is the critical integration point: without it, ISC files can be
    # parsed but cannot transliterate.
    #
    #   doc_hash = Interscript::Isc::DocumentBuilder.build(tree)
    #   node_doc = Interscript::Isc::NodeAdapter.to_interscript_node(doc_hash)
    #   Interscript.transliterate_node(node_doc, "main", "hello")
    #
    class NodeAdapter
      def self.to_interscript_node(isc_doc)
        new(isc_doc).build
      end

      def initialize(isc_doc)
        @isc_doc = isc_doc
      end

      def build
        Interscript::Node::Document.new.tap do |doc|
          doc.metadata = build_metadata
          doc.tests = build_tests
          doc.aliases = build_aliases
          build_stages.each { |name, stage| doc.stages[name] = stage }
          doc.name = @isc_doc[:system_code]
        end
      end

      private

      def build_metadata
        meta = Interscript::Node::MetaData.new
        @isc_doc[:metadata].each do |key, value|
          meta[key.to_sym] = value
        end
        meta
      end

      def build_tests
        return nil if @isc_doc[:tests].empty?

        tests = Interscript::Node::Tests.new
        @isc_doc[:tests].each do |t|
          tests.data << [t[:input], t[:expected]]
        end
        tests
      end

      def build_aliases
        @isc_doc[:aliases].each_with_object({}) do |a, h|
          h[a[:name].to_sym] = convert_item(a[:value])
        end
      end

      def build_stages
        @isc_doc[:stages].each_with_object({}) do |stage, h|
          h[stage[:name].to_sym] = build_stage(stage)
        end
      end

      def build_stage(stage_def)
        stage = Interscript::Node::Stage.new(stage_def[:name].to_sym)
        stage_def[:body].each do |item|
          case item[:kind]
          when :parallel
            group = Interscript::Node::Group::Parallel.new
            item[:rules].each { |r| group.children << build_rule(r) }
            stage.children << group
          when :sequence
            item[:rules].each { |r| stage.children << build_rule(r) }
          when :bare_rule
            stage.children << build_rule(item[:rule])
          when :run
            stage.children << build_run_rule(item)
          when :separate
            stage.children << Interscript::Node::Rule::Sub.new(
              Interscript::Node::Item::String.new(" "),
              Interscript::Node::Item::String.new(item[:separator]&.value || "-"),
            )
          when :string_case
            sym = item[:op] == "title_case" ? :title_case : item[:op].to_sym
            stage.children << sym
          when :compose
            stage.children << :compose
          when :funcall
            stage.children << Interscript::Node::Rule::Funcall.new(
              item[:name].to_sym,
              **item[:kwargs].transform_keys(&:to_sym),
            )
          end
        end
        stage
      end

      def build_rule(rule_def)
        from = convert_item(rule_def[:from])
        to = convert_item(rule_def[:to])
        opts = {}
        %i[before after not_before not_after].each do |k|
          next unless rule_def[:constraints]&.any? { |c| c[:kind] == k }
          constraint = rule_def[:constraints].find { |c| c[:kind] == k }
          opts[k] = convert_item(constraint[:value])
        end
        Interscript::Node::Rule::Sub.new(from, to, **opts)
      end

      def build_run_rule(item)
        stage_ref = Interscript::Node::Item::Stage.new(
          item[:stage].to_sym,
          map: item[:dependency]&.to_sym,
        )
        Interscript::Node::Rule::Run.new(stage_ref)
      end

      def convert_item(item)
        case item
        when Items::StringValue
          Interscript::Node::Item::String.new(item.value)
        when Items::None
          Interscript::Node::Item::String.new("")
        when Items::Primitive
          convert_primitive(item)
        when Items::AliasRef
          Interscript::Node::Item::Alias.new(item.name.to_sym)
        when Items::Capture
          Interscript::Node::Item::CaptureRef.new(item.index)
        when Items::Function
          item.name.to_sym
        when Items::Concat
          convert_concat(item)
        when Items::CaptureGroup
          Interscript::Node::Item::CaptureGroup.new(convert_item(item.inner))
        when Items::Maybe
          Interscript::Node::Item::Maybe.new(convert_item(item.inner))
        when Items::Some
          Interscript::Node::Item::Some.new(convert_item(item.inner))
        when Items::Range
          Interscript::Node::Item::Any.new(
            (item.lo..item.hi).map { |c| Interscript::Node::Item::String.new(c) },
          )
        when Items::Set
          convert_set(item)
        else
          Interscript::Node::Item::String.new(item.to_s)
        end
      end

      def convert_primitive(item)
        # In the Ruby runtime, zero-width primitives are represented as
        # Alias nodes referencing Stdlib symbols. See Stdlib::ALIASES.
        Interscript::Node::Item::Alias.new(item.name.to_sym)
      end

      def convert_concat(concat)
        parts = concat.parts.map { |p| convert_item(p) }
        return parts.first if parts.size == 1
        parts.reduce { |acc, part| acc + part }
      end

      def convert_set(set)
        Interscript::Node::Item::Any.new(
          set.chars.map { |c| Interscript::Node::Item::String.new(c) },
        )
      end
    end
  end
end
