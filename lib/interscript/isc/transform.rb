# frozen_string_literal: true

require "parsanol"

module Interscript
  module Isc
    # Transforms the raw parslet tree into a clean intermediate hash with
    # stable shape for the DocumentBuilder to consume.
    #
    # String escapes are unescaped here. Items are flattened. Constraints
    # are tagged by kind.
    class Transform < Parsanol::Transform
      # String atom: parslet gives us a parslet slice for simple strings,
      # or an array of pieces (escape-sequence fragments interleaved with
      # raw chars) for strings containing escapes. Flatten both to a single
      # StringValue.
      rule(string: simple(:s)) { Items::StringValue.new(s.to_s) }
      rule(string: sequence(:parts)) do
        Items::StringValue.new(Transform.decode_string_parts(parts))
      end
      rule(run: simple(:s)) { s.to_s }

      rule(identifier: simple(:i)) { i.to_s }

      rule(none: simple(:_)) { Items::None.new }
      rule(primitive: simple(:p)) { Items::Primitive.new(p.to_s) }
      rule(function: simple(:f)) { Items::Function.new(f.to_s) }
      rule(alias: {identifier: simple(:n), qualified_name: simple(:q)}) {
        Items::AliasRef.new(q.to_s, map: n.to_s)
      }
      rule(alias: simple(:n)) { Items::AliasRef.new(n.to_s) }
      # Bare identifiers inside any(...) lists parse as :alias_ref (the
      # :alias key only covers direct item position). Unmatched, the hash
      # degraded downstream into the debug string "[:alias_ref, \"name\"]".
      rule(alias_ref: {identifier: simple(:n)}) { Items::AliasRef.new(n.to_s) }
      rule(alias_ref: simple(:n)) { Items::AliasRef.new(n.to_s) }
      rule(ref: subtree(:h)) { Items::Capture.new(h[:digit].to_s.to_i) }
      rule(capture_inner: subtree(:inner)) { Items::CaptureGroup.new(Interscript::Isc::Transform.materialize_item(inner)) }
      rule(maybe_inner: subtree(:inner)) { Items::Maybe.new(Interscript::Isc::Transform.materialize_item(inner)) }
      rule(some_inner: subtree(:inner)) { Items::Some.new(Interscript::Isc::Transform.materialize_item(inner)) }

      rule(dquote: simple(:_)) { '"' }
      rule(backslash: simple(:_)) { "\\" }
      rule(newline: simple(:_)) { "\n" }
      rule(carriage_return: simple(:_)) { "\r" }
      rule(tab: simple(:_)) { "\t" }
      rule(u_lone: simple(:_)) { "U" }
      rule(unicode: simple(:hex)) do
        [hex.to_s.to_i(16)].pack("U")
      rescue
        hex.to_s
      end

      # Shared decoder for the pieces of a :string capture — used by the
      # transform rules above and by the Normalizer's scalar folding. A
      # fragment without an escape key is a raw run slice.
      def self.decode_string_parts(parts)
        Array(parts).map do |p|
          case p
          when Hash
            if p.key?(:run)
              p[:run].to_s
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
              [p[:unicode].to_s.to_i(16)].pack("U")
            elsif p.key?(:u_lone)
              "U"
            else
              p.to_s
            end
          else
            p.to_s
          end
        end.join
      end

      rule(lo: simple(:lo), hi: simple(:hi)) do
        Items::Range.new(lo.to_s, hi.to_s)
      end
      rule(single: simple(:s)) { Items::Set.from_string(s.to_s) }
      # List entries are already Items (strings, primitives, alias refs).
      # Stringifying here baked an object inspect into the char set.
      rule(list: sequence(:arr)) do
        Items::Set.new(arr)
      end
      rule(any: subtree(:h)) do
        # A single alias argument keeps set semantics: the legacy runtime
        # builds Any(Alias) which resolves through Stdlib (Any(nil) for
        # imported aliases). Unwrapped, the bare Alias resolves to the
        # imported charset string and compiles as a literal.
        h.is_a?(Items::AliasRef) ? Items::Set.new([h]) : h
      end

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

      rule(before: subtree(:x)) { {kind: :before, item: x} }
      rule(after: subtree(:x)) { {kind: :after, item: x} }
      rule(not_before: subtree(:x)) { {kind: :not_before, item: x} }
      rule(not_after: subtree(:x)) { {kind: :not_after, item: x} }
      rule(constraints: sequence(:c)) { c }
    end
  end
end
