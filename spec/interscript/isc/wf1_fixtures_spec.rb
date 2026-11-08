# frozen_string_literal: true

require "interscript"

# ISC-WF-1 fixture specs: synthetic maps (a base ruleset map + a
# dependent map using use/override across the dependency boundary) run
# through the full Interscript.transliterate path, with and without
# language selection (spec docs/isc-wf-1.md §8.1-style composition).
RSpec.describe "ISC-WF-1 fixtures" do
  let(:fixture_dir) { File.expand_path("../fixtures/wf1", __dir__) }

  before do
    # Scoped to these examples: locate() resolves only inside the fixture
    # directory while they run. The stub replaces the method, so any
    # memoized load path of the host process is neither read nor written.
    allow(Interscript).to receive(:load_path).and_return([fixture_dir])
    allow(Interscript).to receive(:map_aliases).and_return({})
  end

  describe "the base map" do
    it "expands its own ruleset inline" do
      expect(Interscript.transliterate("wf1-base", "กะาิ")).to eq("kaāi")
    end
  end

  describe "the dependent map" do
    it "imports the base ruleset and overrides one row across the dependency boundary" do
      # "ะ" → a, "า" → ā imported; "ก" → g own row.
      expect(Interscript.transliterate("wf1-dependent", "กะา")).to eq("gaā")
    end

    it "applies the guarded override under the declared language" do
      expect(Interscript.transliterate("wf1-dependent", "กะาิ", language: "tha")).to eq("gaāyy")
    end

    it "leaves the guarded override inert without a language selection" do
      # The replacement happened structurally at load (spec §4.2.3: the
      # guard applies to that row alone), so without a selection the
      # imported "ิ" row is gone and the source character falls through.
      expect(Interscript.transliterate("wf1-dependent", "กะาิ")).to eq("gaāิ")
    end

    it "leaves the guarded override inert for an undeclared language" do
      expect(Interscript.transliterate("wf1-dependent", "กิ", language: "ckv")).to eq("gิ")
    end

    it "keeps the base map's own behavior untouched" do
      expect(Interscript.transliterate("wf1-base", "กิ")).to eq("ki")
    end
  end

  describe "Interscript.transliterate language kwarg" do
    it "passes the selection through to the Interpreter" do
      expect(Interscript.transliterate("wf1-dependent", "กิ", language: :tha)).to eq("gyy")
    end

    it "is rejected with a clear error on the non-Interpreter compilers" do
      # Only the Interpreter implements selection; Ruby's positional-hash
      # rules would otherwise silently swallow the kwarg in the compiled
      # runtimes' call(str, stage).
      expect {
        Interscript.transliterate("wf1-dependent", "ก", compiler: Interscript::Compiler::Ruby, language: "tha")
      }.to raise_error(ArgumentError, /only supported by Interscript::Interpreter/)
    end
  end
end
