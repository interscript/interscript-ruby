# frozen_string_literal: true

require "interscript/isc/transform"
require "interscript/isc/items"

module Interscript
  module Isc
    # Builds an intermediate "document hash" from a raw parslet tree.
    # The hash shape is intentionally simple so it can be:
    #   - inspected in tests
    #   - serialized to JSON IR for cross-runtime conformance
    #   - consumed by interscript-ruby's existing Node::Document builder
    #
    # This is the bridge between the parser and the runtime. It does no
    # semantic validation beyond shape; that lives in the runtime layer.
    class DocumentBuilder
      SCHEMA_VERSION = 1

      def self.build(tree, filename: nil)
        new(tree, filename: filename).build
      end

      def initialize(tree, filename: nil)
        @tree = tree
        @filename = filename
        @transform = Transform.new
      end

      def build
        node = @tree[:system] || @tree
        code = unquote(node[:system_code])

        body = Array(node[:body])
        metadata_hash = {}
        aliases_arr = []
        tests_arr = []
        stages_arr = []
        dependencies_arr = []

        body.each do |item|
          case
          when item[:metadata] then metadata_hash.merge!(extract_metadata(item[:metadata]))
          when item[:aliases]  then aliases_arr.concat(extract_aliases(item[:aliases]))
          when item[:tests]    then tests_arr.concat(extract_tests(item[:tests]))
          when item[:stage]    then stages_arr << extract_stage(item)
          when item[:target]   then dependencies_arr << extract_dependency(item)
          end
        end

        {
          schemaVersion: SCHEMA_VERSION,
          filename: @filename,
          systemCode: code,
          urn: derive_urn(code),
          metadata: metadata_hash,
          aliases: aliases_arr,
          tests: tests_arr,
          stages: stages_arr,
          dependencies: dependencies_arr,
        }
      end

      private

      # Apply Transform to a quoted_string fragment and read back the string value.
      def unquote(fragment)
        return "" if fragment.nil?
        return fragment.to_s unless fragment.is_a?(Hash)
        return fragment.to_s unless fragment.key?(:string)

        out = @transform.apply(fragment)
        out.is_a?(Items::StringValue) ? out.value : out.to_s
      end

      # Apply Transform to an identifier fragment.
      def ident(fragment)
        return "" if fragment.nil?
        return fragment.to_s unless fragment.is_a?(Hash)
        return fragment.to_s unless fragment.key?(:identifier)

        @transform.apply(fragment).to_s
      end

      def derive_urn(code)
        "urn:iso:24229:system:#{code.downcase}"
      end

      def extract_metadata(arr)
        h = {}
        Array(arr).each do |field|
          case
          when field.key?(:specification)
            h[:specification] ||= []
            h[:specification] << unquote(field[:specification])
          when field.key?(:notes)
            h[:notes] ||= []
            Array(field[:notes]).each { |n| h[:notes] << unquote(n) }
          when field.key?(:note)
            h[:notes] ||= []
            h[:notes] << unquote(field[:note])
          when field.key?(:provenance)
            h[:provenance] ||= []
            h[:provenance] << unquote(field[:provenance])
          when field.key?(:relations)
            h[:relations] = extract_relations(field[:relations])
          when field.key?(:description)
            h[:description] = field[:description].to_s.strip
          when field.key?(:field_name)
            # Generic field: identifier + raw value
            name = ident(field[:field_name]).to_sym
            raw = field[:field_value]
            val_str = case raw
                      when Hash
                        raw.key?(:string) ? unquote(raw) : (raw[:raw]&.to_s || "").strip
                      when nil then ""
                      else raw.to_s.strip
                      end
            h[name] = val_str
          else
            # Specific named field (authority, name, system_status, etc.)
            field.each do |key, val|
              next if val.nil?
              h[key] = val.is_a?(Hash) && val.key?(:string) ? unquote(val) : val.to_s
            end
          end
        end
        h
      end

      def extract_relations(arr)
        Array(arr).map do |r|
          {
            type: r[:type].to_s,
            system: unquote(r[:system]),
            note: r[:note] && unquote(r[:note]),
          }.compact
        end
      end

      def extract_aliases(arr)
        Array(arr).map do |a|
          { name: ident(a[:name]), value: materialize(a[:value]) }
        end
      end

      def extract_tests(arr)
        Array(arr).map do |t|
          {
            input: unquote(t[:input]),
            expected: unquote(t[:expected]),
            note: t[:note] && unquote(t[:note]),
          }.compact
        end
      end

      def extract_stage(item)
        node = item[:stage]
        name = ident(item[:stage_name])
        body = Array(node).flat_map { |n| extract_stage_items(n) }
        { name: name, body: body }
      end

      def extract_stage_items(n)
        case
        when n[:sequence]  then [{ kind: :sequence,  rules: Array(n[:sequence]).map { |r| extract_rule(r) } }]
        when n[:parallel]  then [{ kind: :parallel,  rules: Array(n[:parallel]).map { |r| extract_rule(r) } }]
        when n[:separate]  then [{ kind: :separate }]
        when n[:compose]   then [{ kind: :compose }]
        when n[:case]      then [{ kind: :string_case, op: n[:case].to_s }]
        when n[:dep]       then [{ kind: :run, dependency: ident(n[:dep]), stage: ident(n[:stage]) }]
        when n[:bare_rule] then [{ kind: :bare_rule, rule: extract_rule(n[:bare_rule]) }]
        else []
        end
      end

      def extract_rule(r)
        {
          from: materialize(r[:from]),
          to: materialize(r[:to]),
          constraints: extract_constraints(r[:constraints]),
        }
      end

      def extract_constraints(arr)
        Array(arr).map do |c|
          # c is a one-key hash like { before: <item> }. Apply Transform to
          # get { kind: :before, item: <materialized> }.
          transformed = @transform.apply(c)
          if transformed.is_a?(Hash) && transformed.key?(:kind)
            transformed
          else
            # Transform rule didn't match — likely an empty/None constraint.
            { kind: nil, item: nil }
          end
        end
      end

      def extract_dependency(item)
        {
          target: unquote(item[:target]),
          alias: item[:alias] && ident(item[:alias]),
        }.compact
      end

      # Convert a parslet tree fragment into a concrete Item object via Transform.
      def materialize(fragment)
        case fragment
        when Hash
          if fragment.key?(:concatenation)
            Transform.new.apply(fragment)
          else
            Transform.new.apply(concatenation: [fragment])
          end
        when Array
          Transform.new.apply(concatenation: fragment)
        when NilClass
          Items::None.new
        else
          fragment
        end
      end
    end
  end
end
