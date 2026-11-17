# frozen_string_literal: true

require "interscript"

# WO20 differential-fuzz finding (maps#292): an alias whose body is a
# top-level `maybe(...)` was miscompiled by the ruby reference runtime —
# the optionality suffix bound to the inner expression's LAST atom
# (`(?:x|y|z)[1-3]?`) instead of the whole body (`(?:(?:x|y|z)[1-3])?`),
# so the rule never matched and the transliteration silently returned the
# input unchanged. ts/py/rs were the consistent reference; these rows pin
# the agreed outputs (rs `iscrs transliterate` on the same fixture).
RSpec.describe "fuzz: alias body maybe(...)" do
  let(:fixture_dir) { File.expand_path("../fixtures/fuzz", __dir__) }

  before do
    allow(Interscript).to receive(:load_path).and_return([fixture_dir])
    allow(Interscript).to receive(:map_aliases).and_return({})
  end

  it "fires the rule for a real match" do
    expect(Interscript.transliterate("alias-maybe", "y")).to eq("RyR")
  end

  it "fires the rule with empty matches at every boundary (maps#292 repro)" do
    expect(Interscript.transliterate("alias-maybe", "abc")).to eq("RaRbRcR")
  end
end
