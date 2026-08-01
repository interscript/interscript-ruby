# frozen_string_literal: true

module Interscript
  module Isc
    module Items
      # String-like value carried through the transform. We don't subclass
      # String because we want to distinguish a literal string atom from
      # a Concat.
      class StringValue
        attr_reader :value

        def initialize(value)
          @value = value
        end

        def to_s
          @value
        end

        def ==(other)
          other.is_a?(StringValue) && other.value == @value
        end

        def inspect
          "StringValue(#{@value.inspect})"
        end
      end

      class None
        def to_s
          ""
        end

        def inspect
          "None"
        end
      end

      class Primitive
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def inspect
          "Primitive(#{@name})"
        end
      end

      class AliasRef
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def inspect
          "AliasRef(#{@name})"
        end
      end

      class Capture
        attr_reader :index

        def initialize(index)
          @index = index
        end

        def inspect
          "Capture(\\#{@index})"
        end
      end

      # Wraps a sub-expression that captures its match for later reference via ref(N).
      class CaptureGroup
        attr_reader :inner

        def initialize(inner)
          @inner = inner
        end

        def inspect
          "CaptureGroup(#{@inner.inspect})"
        end
      end

      # Wraps an optional sub-expression (matches zero or one time).
      class Maybe
        attr_reader :inner

        def initialize(inner)
          @inner = inner
        end

        def inspect
          "Maybe(#{@inner.inspect})"
        end
      end

      class Range
        attr_reader :lo, :hi

        def initialize(lo, hi)
          @lo = lo
          @hi = hi
        end

        def inspect
          "Range(#{@lo}..#{@hi})"
        end
      end

      class Set
        attr_reader :chars

        def initialize(chars)
          @chars = chars.to_a
        end

        def self.from_string(s)
          new(s.chars)
        end

        def self.from_strings(arr)
          new(arr.flat_map(&:chars))
        end

        def inspect
          "Set(#{@chars.join})"
        end
      end

      class Concat
        attr_reader :parts

        def initialize(parts)
          @parts = parts
        end

        def self.from_parts(arr)
          flattened = arr.flat_map do |p|
            p.is_a?(Concat) ? p.parts : [p]
          end
          case flattened.size
          when 0 then None.new
          when 1 then flattened.first
          else new(flattened)
          end
        end

        def inspect
          "Concat(#{@parts.map(&:inspect).join(', ')})"
        end
      end
    end
  end
end
