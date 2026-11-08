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
          # A comment-only or empty tests block captures as its raw
          # text through the artifact; the DSL grammar folds it. Both
          # normalize to no tests.
          items = block[:tests].is_a?(Array) ? block[:tests] : []
          {tests: merge_tests(items)}
        elsif block.key?(:stage)
          {stage_name: scalar(block[:stage_name]), stage: normalize_stage_items(block[:stage])}
        elsif block.key?(:ruleset)
          # ISC-WF-1 W1: same shape as a stage, under the ruleset key.
          {ruleset_name: scalar(block[:ruleset_name]), ruleset: normalize_stage_items(block[:ruleset])}
        elsif block.key?(:languages)
          # ISC-WF-1 W3: `languages a, b` folds to a plain list of names.
          # One language captures as a single {language:} hash, several as
          # a list.
          langs = block[:languages]
          list = langs.is_a?(Hash) ? [langs] : Array(langs)
          {languages: list.map { |l| l.is_a?(Hash) ? scalar(l[:language]) : scalar(l) }}
        elsif block.key?(:target)
          {target: scalar(block[:target]), alias: scalar(block[:alias])}.compact
        else
          block
        end
      end

      # A capture-free block (empty or comment-only body — comments are
      # consumed as whitespace) folds to a raw slice under .as; the .parg
      # artifact's empty capture is an array. Match it.
      def normalize_stage_items(items)
        Array(items).map do |item|
          if item.is_a?(Hash)
            %i[parallel sequence].each do |k|
              item = {k => []} if item.key?(k) && !item[k].is_a?(Array)
            end
            # ISC-WF-1 W1/W2: `use` items get their reference identifiers
            # folded to strings; the override rules keep their parslet
            # shape (DocumentBuilder materializes them through Transform).
            if item.key?(:use) && item[:use].is_a?(Hash)
              use = item[:use]
              item = {use: {
                use_alias: use[:use_alias] && scalar(use[:use_alias]),
                qualified_name: use[:qualified_name] && scalar(use[:qualified_name]),
                use_overrides: use[:use_overrides]
              }.compact}
            end
          end
          item
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
