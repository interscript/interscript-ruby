# frozen_string_literal: true

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

      # Metadata fields that the Ruby DSL stores as Arrays (STANDARD_ARRAY_KEYS).
      # ISC stores them as generic fields, so we wrap in an Array to match.
      ARRAY_METADATA_FIELDS = %i[notes implementation_notes original_notes url].freeze

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

      def unescape_braces(text)
        text.gsub(/\\([{}\\])/, '\1')
      end

      def parse_array_field(val)
        return [] if val.nil? || val.to_s.strip.empty?
        # If the value contains newlines or `- ` markers, split into items
        items = val.to_s.split(/\n+/)
                       .map { |l| l.strip.sub(/\A-\s*/, "") }
                       .reject(&:empty?)
        return [val.to_s.strip] if items.empty?
        items
      end

      def normalize_heredoc(text)
        lines = text.lines.map(&:chomp)
        content_lines = lines.reject { |l| l.strip.empty? }
        return "" if content_lines.empty?
        return content_lines.first.strip if content_lines.size == 1

        # YAML-style dedent: strip the minimum indent across all non-blank
        # lines. The first line's indent may have been partially consumed
        # by the grammar, so we compute min_indent from lines 2+ and treat
        # the first line as having at least that much indent.
        min_indent = content_lines
          .drop(1)
          .map { |l| l[/\A[ \t]*/].length }
          .min || 0

        lines.map do |l|
          if l.strip.empty?
            ""
          elsif l[/\A[ \t]*/].length >= min_indent
            l[min_indent..]
          else
            l.strip
          end
        end.join("\n").strip
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
            Array(field[:notes]).each do |n|
              note_val = n.is_a?(Hash) ? n[:note] : n
              h[:notes] << normalize_heredoc(unquote(note_val).to_s)
            end
          when field.key?(:note)
            h[:notes] ||= []
            h[:notes] << normalize_heredoc(unquote(field[:note]).to_s)
          when field.key?(:provenance)
            h[:provenance] ||= []
            h[:provenance] << unquote(field[:provenance])
          when field.key?(:relations)
            h[:relations] = extract_relations(field[:relations])
          when field.key?(:description)
            h[:description] = normalize_heredoc(unescape_braces(field[:description].to_s)) + "\n"
          when field.key?(:field_name)
            # Generic field: identifier + raw value
            name = ident(field[:field_name]).to_sym
            if field.key?(:field_block)
              val = normalize_heredoc(unescape_braces(field[:field_block].to_s))
            else
              raw = field[:field_value]
              val = case raw
                    when Hash
                      raw.key?(:string) ? unquote(raw) : (raw[:raw]&.to_s || "").strip
                    when nil then ""
                    else raw.to_s.strip
                    end
            end
            # DSL stores these as Arrays — match that convention.
            if ARRAY_METADATA_FIELDS.include?(name)
              h[name] = parse_array_field(val)
            else
              h[name] = val
            end
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
          next { input: "", expected: "" } unless t.is_a?(Hash)

          input_val = t[:input]
          expected_val = t[:expected]
          note_val = t[:note]

          {
            input: input_val.is_a?(Hash) ? unquote(input_val) : input_val.to_s,
            expected: expected_val.is_a?(Hash) ? unquote(expected_val) : expected_val.to_s,
            note: note_val.is_a?(Hash) ? unquote(note_val) : note_val&.to_s,
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
        return [] unless n.is_a?(Hash)
        case
        when n[:sequence]  then [{ kind: :sequence,  rules: filter_noop(Array(n[:sequence]).map { |r| extract_rule(r) }) }]
        when n[:parallel]  then [{ kind: :parallel,  rules: filter_noop(Array(n[:parallel]).map { |r| extract_rule(r) }) }]
        when n[:separate]  then [{ kind: :separate, separator: n[:separator] ? materialize(n[:separator]) : nil }]
        when n[:compose]   then [{ kind: :compose }]
        when n[:case]      then [{ kind: :string_case, op: n[:case].to_s }]
        when n[:dep]       then [{ kind: :run, dependency: ident(n[:dep]), stage: ident(n[:stage]) }]
        when n[:run_stage_only] then [{ kind: :run, dependency: nil, stage: ident(n[:run_stage_only][:stage]) }]
        when n[:bare_rule] then [{ kind: :bare_rule, rule: extract_rule(n[:bare_rule]) }]
        when n[:comment]   then []
        when n[:noop]      then []
        else []
        end
      end

      # Filter out noop rules (from: None, to: None) created by empty
      # parallel/sequence blocks that contain only comments or whitespace.
      def filter_noop(rules)
        rules.reject do |r|
          r.is_a?(Hash) &&
            r[:from].is_a?(Items::None) &&
            r[:to].is_a?(Items::None)
        end
      end

      def extract_rule(r)
        from_val = r.is_a?(Hash) ? r[:from] : nil
        to_val = r.is_a?(Hash) ? r[:to] : nil
        constraints_val = r.is_a?(Hash) ? r[:constraints] : nil
        {
          from: from_val ? materialize(from_val) : Items::None.new,
          to: to_val ? materialize(to_val) : Items::None.new,
          constraints: extract_constraints(constraints_val),
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
