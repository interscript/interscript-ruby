# frozen_string_literal: true

module Interscript
  module Isc
    # Normalizes the raw parslet tree into the documented Parser.parse
    # shape: scalar leaves (string/identifier nodes) become plain
    # strings, metadata field pairs become keyed hashes, and arrow-form
    # test pairs merge into single {input:, expected:} entries. Deeper
    # item trees (rule from/to, constraints, kwargs) keep their parslet
    # shape — DocumentBuilder materializes those through Transform.
    class Normalizer
      def self.normalize(tree)
        new(tree).normalize
      end

      def initialize(tree)
        @tree = tree
      end

      def normalize
        system = @tree[:system]
        return @tree unless system

        {
          system: {
            system_code: scalar(system[:system_code]),
            body: Array(system[:body]).map { |block| normalize_block(block) }
          }
        }
      end

      private

      # {string: [{char: "B"@8}, ...]} and {identifier: "main"@31}
      # become plain strings.
      def scalar(node)
        return node if node.is_a?(::String) || node.nil?
        if node.key?(:string)
          # Parts are {char:} hashes and escape fragments ({dquote:},
          # {unicode:}, …) in the general grammar; some constructions
          # (e.g. the rababa directive) capture bare slices instead.
          # Escapes decode via the shared fold — folding only :char here
          # silently dropped every escaped character.
          Interscript::Isc::Transform.decode_string_parts(node[:string])
        elsif node.key?(:identifier)
          node[:identifier].to_s
        elsif node.key?(:raw)
          node[:raw].to_s
        else
          node
        end
      end

      def normalize_block(block)
        return block unless block.is_a?(Hash)
        if block.key?(:metadata)
          {metadata: Array(block[:metadata]).map { |field| normalize_meta_field(field) }}
        elsif block.key?(:aliases)
          {
            aliases: Array(block[:aliases]).map do |alias_def|
              {name: scalar(alias_def[:name]), value: alias_def[:value]}.compact
            end
          }
        elsif block.key?(:tests)
          {tests: merge_tests(Array(block[:tests]))}
        elsif block.key?(:stage)
          {stage_name: scalar(block[:stage_name]), stage: block[:stage]}
        elsif block.key?(:target)
          {target: scalar(block[:target]), alias: scalar(block[:alias])}.compact
        else
          block
        end
      end

      # {field_name: {identifier: "authority"}, field_value: {string: [...]}}
      # becomes {authority: "BGN-PCGN"}.
      def normalize_meta_field(field)
        return field unless field.is_a?(Hash) && field.key?(:field_name)

        name = scalar(field[:field_name]).to_sym
        value = field.key?(:field_block) ? field[:field_block] : scalar(field[:field_value])
        {name => value}
      end

      # The arrow form usually parses as one {input:, expected:} hash
      # per test; tolerate adjacent single-key entries as well.
      def merge_tests(entries)
        merged = []
        pending_input = nil
        entries.each do |entry|
          next unless entry.is_a?(Hash)
          if entry.key?(:input) && entry.key?(:expected)
            merged << {input: scalar(entry[:input]), expected: scalar(entry[:expected])}
            pending_input = nil
          elsif entry.key?(:input)
            pending_input = scalar(entry[:input])
          elsif entry.key?(:expected)
            merged << {input: pending_input, expected: scalar(entry[:expected])}
            pending_input = nil
          else
            merged << entry
          end
        end
        merged << {input: pending_input, expected: ""} if pending_input
        merged
      end
    end
  end
end
