# frozen_string_literal: true

module Interscript
  # A3 (WO59): mechanical equivalence checking between two systems.
  #
  # Probes a sample set through both systems and reports the agreement
  # ratio plus the minimal distinguishing samples. The sample set is
  # caller-supplied or derived from the systems' own embedded tests.
  class Equivalence
    def self.check(first, second, samples:)
      new(first, second).check(samples)
    end

    # Embedded test inputs of the given systems (the natural probe set
    # for near-equivalent authorities).
    def self.samples_from_tests(*codes)
      codes.flat_map do |code|
        Array(Interscript.parse(code).tests&.data).map(&:first).compact
      end.uniq
    end

    def initialize(first, second)
      @first = first
      @second = second
    end

    def check(samples)
      distinguishing = []
      tested = 0
      matched = 0
      samples.each do |sample|
        tested += 1
        a = Interscript.transliterate(@first, sample)
        b = Interscript.transliterate(@second, sample)
        if a == b
          matched += 1
        else
          distinguishing << { sample: sample, first: a, second: b }
        end
      end
      ratio = tested.zero? ? 1.0 : matched.fdiv(tested)
      { tested: tested, matched: matched, ratio: ratio,
        distinguishing: distinguishing }
    end
  end
end
