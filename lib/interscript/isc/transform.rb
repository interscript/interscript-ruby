# frozen_string_literal: true

require "parslet"
require "interscript/isc/items"

module Interscript
  module Isc
    # Transforms the raw parslet tree into a clean intermediate hash with
    # stable shape for the DocumentBuilder to consume.
    #
    # String escapes are unescaped here. Items are flattened. Constraints
    # are tagged by kind.
    class Transform < Parslet::Transform
      # String atom: parslet gives us a parslet slice for simple strings,
      # or an array of pieces (escape-sequence fragments interleaved with
      # raw chars) for strings containing escapes. Flatten both to a single
      # StringValue.
      rule(string: simple(:s)) { Items::StringValue.new(s.to_s) }
      rule(string: sequence(:parts)) do
        combined = parts.map do |p|
          case p
          when Hash
            # Escape sequence fragment: e.g. {newline: "n"}, {unicode: "1234"},
            # {dquote: '"'}, {char: "a"}
            if p.key?(:char)
              p[:char].to_s
            elsif p.key?(:newline)
              "\n"
            elsif p.key?(:carriage_return)
              "\r"
            elsif p.key?(:tab)
              "\t"
            elsif p.key?(:dquote)
              '"'
            elsif p.key?(:backslash)
              "\\"
            elsif p.key?(:unicode)
              code = p[:unicode].to_s
              [code].pack("U")
            else
              p.to_s
            end
          else
            p.to_s
          end
        end.join
        Items::StringValue.new(combined)
      end
      rule(char: simple(:c)) { c.to_s }

      rule(identifier: simple(:i)) { i.to_s }

      rule(none: simple(:_)) { Items::None.new }
      rule(primitive: simple(:p)) { Items::Primitive.new(p.to_s) }
      rule(function: simple(:f)) { Items::Function.new(f.to_s) }
      rule(alias: simple(:n)) { Items::AliasRef.new(n.to_s) }
      rule(ref: subtree(:h)) { Items::Capture.new(h[:digit].to_s.to_i) }
      rule(capture_inner: subtree(:inner)) { Items::CaptureGroup.new(materialize_item(inner)) }
      rule(maybe_inner: subtree(:inner)) { Items::Maybe.new(materialize_item(inner)) }

      rule(dquote: simple(:_)) { '"' }
      rule(backslash: simple(:_)) { "\\" }
      rule(newline: simple(:_)) { "\n" }
      rule(carriage_return: simple(:_)) { "\r" }
      rule(tab: simple(:_)) { "\t" }
      rule(unicode: simple(:hex)) do
        [hex.to_s].pack("U")
      rescue StandardError
        hex.to_s
      end

      rule(lo: simple(:lo), hi: simple(:hi)) do
        Items::Range.new(lo.to_s, hi.to_s)
      end
      rule(single: simple(:s)) { Items::Set.from_string(s.to_s) }
      rule(list: sequence(:arr)) do
        Items::Set.from_strings(arr.map(&:to_s))
      end
      rule(any: subtree(:h)) { h }

      rule(concatenation: subtree(:parts)) do
        Items::Concat.from_parts(Array(parts))
      end

      def self.materialize_item(fragment)
        case fragment
        when Hash
          if fragment.key?(:concatenation)
            new.apply(fragment)
          else
            new.apply(concatenation: [fragment])
          end
        when Array
          new.apply(concatenation: fragment)
        when NilClass
          Items::None.new
        else
          fragment
        end
      end

      def materialize_item(fragment)
        self.class.materialize_item(fragment)
      end

      rule(before: subtree(:x))     { { kind: :before, item: x } }
      rule(after: subtree(:x))      { { kind: :after, item: x } }
      rule(not_before: subtree(:x)) { { kind: :not_before, item: x } }
      rule(not_after: subtree(:x))  { { kind: :not_after, item: x } }
      rule(constraints: sequence(:c)) { c }
    end
  end
end
