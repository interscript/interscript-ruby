# frozen_string_literal: true

require "interscript/isc/items"

module Interscript
  module Isc
    # Serializes a document hash back to ISC source text.
    # This is the reverse of Parser → DocumentBuilder.
    #
    #   isc_source = Serializer.serialize(doc_hash)
    #
    class Serializer
      def self.serialize(doc_hash)
        new(doc_hash).serialize
      end

      def initialize(doc_hash)
        @doc = doc_hash
        @out = +""
      end

      def serialize
        emit_system_open
        emit_metadata if @doc[:metadata]&.any?
        emit_tests if @doc[:tests]&.any?
        emit_aliases if @doc[:aliases]&.any?
        emit_dependencies if @doc[:dependencies]&.any?
        emit_stages
        emit_system_close
        @out
      end

      private

      def emit_system_open
        @out << %(system "#{@doc[:systemCode]}" {\n)
      end

      def emit_system_close
        @out << "}\n"
      end

      def emit_blank
        @out << "\n"
      end

      def emit_metadata
        @out << "\nmetadata {\n"
        @doc[:metadata].each do |key, val|
          emit_metadata_field(key, val)
        end
        @out << "}\n"
      end

      def emit_metadata_field(key, val)
        k = key.to_s
        case k
        when "description"
          emit_description(val)
        when "notes", "implementation_notes", "original_notes"
          emit_notes(k, val)
        else
          case val
          when Array
            val.each { |v| @out << "  #{k} #{emit_meta_value(v)}\n" }
          when String
            @out << "  #{k} #{emit_meta_value(val)}\n"
          when NilClass
            @out << "  #{k}\n"
          else
            @out << "  #{k} #{val}\n"
          end
        end
      end

      def emit_description(val)
        if val.is_a?(Array)
          val = val.join(" ")
        end
        s = val.to_s.strip
        if s.empty?
          @out << "  description { }\n"
        elsif s.include?("\n") || s.length > 60
          escaped = s.gsub("\\", "\\\\\\\\").gsub("{", "\\{").gsub("}", "\\}")
          @out << "  description {\n    #{escaped.split("\n").join("\n    ")}\n  }\n"
        else
          @out << "  description { #{escaped = s.gsub("\\", "\\\\\\\\").gsub("{", "\\{").gsub("}", "\\}")} }\n"
        end
      end

      def emit_notes(key, val)
        arr = val.is_a?(Array) ? val : [val]
        if arr.empty?
          @out << "  #{key} { }\n"
        else
          @out << "  #{key} {\n"
          arr.each do |note|
            escaped = note.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
            @out << "    note \"#{escaped}\"\n"
          end
          @out << "  }\n"
        end
      end

      def emit_meta_value(val)
        s = val.to_s
        # Quote values that contain spaces, special chars, or look like numbers
        if s.match?(/[\s"{}#]/) || s.empty?
          s.inspect
        else
          s
        end
      end

      def emit_tests
        @out << "\ntests {\n"
        @doc[:tests].each do |t|
          @out << %(  "#{escape(t[:input])}" -> "#{escape(t[:expected])}")
          @out << %( note "#{escape(t[:note])}") if t[:note]
          @out << "\n"
        end
        @out << "}\n"
      end

      def emit_aliases
        @out << "\naliases {\n"
        @doc[:aliases].each do |a|
          @out << "  #{a[:name]} = #{emit_item(a[:value])}\n"
        end
        @out << "}\n"
      end

      def emit_dependencies
        @doc[:dependencies].each do |d|
          dep = %(dependency "#{d[:target]}")
          dep << %(, as: #{d[:alias]}) if d[:alias]
          @out << dep << "\n"
        end
        @out << "\n" if @doc[:dependencies].any?
      end

      def emit_stages
        @doc[:stages].each do |stage|
          @out << "\nstage #{stage[:name]} {\n"
          stage[:body].each { |item| emit_stage_item(item) }
          @out << "}\n"
        end
      end

      def emit_stage_item(item)
        case item[:kind]
        when :parallel
          @out << "  parallel {\n"
          item[:rules].each { |r| emit_rule(r, 4) }
          @out << "  }\n"
        when :sequence
          @out << "  sequence {\n"
          item[:rules].each { |r| emit_rule(r, 4) }
          @out << "  }\n"
        when :bare_rule
          emit_rule(item[:rule], 2)
        when :run
          dep = item[:dependency]
          stage = item[:stage]
          if dep
            @out << "  run map.#{dep}.stage.#{stage}\n"
          else
            @out << "  run stage.#{stage}\n"
          end
        when :separate
          sep = item[:separator]
          @out << "  separate separator #{emit_item(sep)}\n"
        when :compose
          @out << "  compose\n"
        when :string_case
          @out << "  #{item[:op]}\n"
        end
      end

      def emit_rule(rule, indent)
        pad = " " * indent
        from_str = emit_item(rule[:from])
        to_str = emit_item(rule[:to])
        constraints_str = rule[:constraints]&.map { |c| emit_constraint(c) }&.join(" ") || ""
        @out << "#{pad}sub #{from_str} #{to_str}"
        @out << " #{constraints_str}" unless constraints_str.empty?
        @out << "\n"
      end

      def emit_constraint(constraint)
        "#{constraint[:kind]} #{emit_item(constraint[:item])}"
      end

      def emit_item(item)
        return "none" unless item

        case item
        when Items::StringValue
          escape_string(item.value)
        when Items::None
          "none"
        when Items::Primitive
          item.name
        when Items::Function
          item.name
        when Items::AliasRef
          item.name
        when Items::Capture
          "ref(#{item.index})"
        when Items::CaptureGroup
          "capture(#{emit_item(item.inner)})"
        when Items::Concat
          item.parts.map { |p| emit_item(p) }.join(" + ")
        when Items::Set
          %(any("#{item.chars.map { |c| escape(c) }.join}"))
        when Items::Range
          %(any("#{escape(item.lo)}".."#{escape(item.hi)}"))
        when Items::Maybe
          "maybe(#{emit_item(item.inner)})"
        when Items::Some
          "some(#{emit_item(item.inner)})"
        else
          item.to_s
        end
      end

      def escape_string(str)
        escaped = str.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
        "\"#{escaped}\""
      end

      def escape(str)
        str.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
      end
    end
  end
end
