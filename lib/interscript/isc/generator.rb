# frozen_string_literal: true

module Interscript
  module Isc
    # Serializes a Node::Document back to ISC source — the inverse of
    # Parser + DocumentBuilder + NodeAdapter. The Python compiler
    # bridge generates ISC from in-memory documents because the
    # rewritten python runtime executes ISC sources, not compiled
    # modules. Every construct the generator emits must round-trip:
    # spec/interscript/isc/generator_spec.rb pins behavior equality.
    class Generator
      def self.generate(doc)
        new(doc).generate
      end

      def initialize(doc)
        @doc = doc
      end

      def generate
        out = "system #{quote(@doc.name.to_s)} {\n"
        out << generate_aliases
        out << generate_dependencies
        @doc.stages.each do |name, group|
          out << "  stage #{name} {\n" << generate_group(group, 2) << "  }\n"
        end
        out << "}\n"
      end

      private

      def generate_aliases
        return "" if @doc.aliases.empty?

        out = +"  aliases {\n"
        @doc.aliases.each_value do |alias_def|
          out << "    #{alias_def.name} = #{item(alias_def.data)}\n"
        end
        out << "  }\n"
      end

      def generate_dependencies
        return "" if @doc.dependencies.empty?

        out = +""
        @doc.dependencies.each do |dep|
          out << "  dependency #{quote(dep.full_name.to_s)}"
          out << " as #{dep.name}" if dep.name
          out << "\n"
        end
        out
      end

      def generate_group(group, indent)
        Array(group.children).map { |child| emit(child, indent) }.join
      end

      def emit(child, indent)
        pad = " " * indent
        case child
        when Interscript::Node::Group::Parallel
          "#{pad}parallel {\n#{generate_group(child, indent + 2)}#{pad}}\n"
        when Interscript::Node::Group
          generate_group(child, indent)
        when Interscript::Node::Rule::Sub
          rule(child, pad)
        when Interscript::Node::Rule::Run
          "#{pad}run #{run_target(child)}\n"
        when Interscript::Node::Rule::Funcall
          funcall(child, pad)
        else
          raise UnsupportedConstruct, "cannot generate #{child.class} as a stage item"
        end
      end

      def rule(sub, pad)
        out = "#{pad}sub {\n"
        out << "#{pad}  from #{item(sub.from)}\n"
        out << "#{pad}  to #{target(sub.to)}\n"
        {before: sub.before, after: sub.after,
         not_before: sub.not_before, not_after: sub.not_after}.each do |kw, value|
          out << "#{pad}  #{kw} #{item(value)}\n" if value
        end
        out << "#{pad}}\n"
      end

      def target(to)
        return to.to_s if %i[upcase downcase].include?(to)

        item(to)
      end

      def run_target(run)
        stage = run.stage
        stage.map ? "map.#{stage.map}.stage.#{stage.name}" : "stage.#{stage.name}"
      end

      def funcall(rule, pad)
        case rule.name
        when :separate
          separator = rule.kwargs[:separator]
          return "#{pad}separate\n" if separator.nil?

          "#{pad}separate separator #{item(separator)}\n"
        when :title_case
          word_separator = rule.kwargs[:word_separator]
          return "#{pad}title_case\n" if word_separator.nil?

          "#{pad}title_case word_separator: #{quote(word_separator)}\n"
        else
          unless rule.kwargs.empty?
            raise UnsupportedConstruct,
              "cannot generate #{rule.name}(...) with kwargs as ISC"
          end

          "#{pad}#{rule.name}\n"
        end
      end

      # -- items --

      def item(i)
        case i
        when Interscript::Node::Item::String
          quote(i.data)
        when Interscript::Node::Item::Any
          any(i)
        when Interscript::Node::Item::Alias
          i.map ? "#{i.map}.#{identifier(i.name)}" : identifier(i.name)
        when Interscript::Node::Item::CaptureGroup
          "capture(#{item(i.data)})"
        when Interscript::Node::Item::CaptureRef
          "ref(#{i.id})"
        when Interscript::Node::Item::Group
          i.children.map { |c| item(c) }.join(" + ")
        when Interscript::Node::Item::Maybe
          "maybe(#{item(i.data)})"
        when Interscript::Node::Item::Some
          "some(#{item(i.data)})"
        when ::String
          quote(i)
        when ::Symbol
          identifier(i)
        else
          raise UnsupportedConstruct, "cannot generate #{i.class} as an item"
        end
      end

      def any(node)
        case node.value
        when ::String
          "any(#{quote(node.value)})"
        when ::Range
          "any(#{quote(node.value.first)}..#{quote(node.value.last)})"
        when ::Array
          inner = node.value.map { |v| item(v) }
          return "any(#{inner.first})" if inner.size == 1

          "any([#{inner.join(", ")}])"
        else
          raise UnsupportedConstruct, "cannot generate Any of #{node.value.class}"
        end
      end

      def identifier(sym)
        name = sym.to_s
        raise UnsupportedConstruct, "#{name.inspect} is not a bare identifier" unless /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(name)

        name
      end

      ESCAPE_MAP = {
        "\\" => "\\\\",
        "\"" => "\\\""
      }.freeze

      def quote(str)
        escaped = str.to_s.gsub(/[\\"]/) { |c| ESCAPE_MAP.fetch(c) }
        # Only control and DEL characters need escaping; both parsers
        # read raw UTF-8, including astral code points (surrogate-pair
        # \u escapes are NOT re-joined).
        escaped = escaped.each_char.map { |c|
          (c.ord < 0x20 || c.ord == 0x7f) ? format("\\u%04x", c.ord) : c
        }.join
        "\"" + escaped + "\""
      end

      class UnsupportedConstruct < StandardError; end
    end
  end
end
