# frozen_string_literal: true

require "json"
require "interscript/ml"

# The frozen-fixture contract (interscript-models/conformance/) — the
# ruby runtime must reproduce a model's vectors byte-exactly under the
# declared decode mode, or the change does not merge.
RSpec.describe "frozen conformance fixtures" do
  before do
    skip "set CONFORMANCE_VECTORS and SECRYST_E2E_ZIP" unless
      ENV["CONFORMANCE_VECTORS"] && ENV["SECRYST_E2E_ZIP"]
  end

  it "reproduces the vectors byte-exactly (single-row-greedy)" do
    vectors = JSON.parse(File.read(ENV["CONFORMANCE_VECTORS"]))
    expect(vectors["decode"]["mode"]).to eq("single-row-greedy")
    model = Interscript::ML::Translator.new(model_file: ENV["SECRYST_E2E_ZIP"])
    failures = []
    vectors["vectors"].each do |v|
      got = model.translate(v["src"])
      failures << "#{v["src"].inspect} -> #{got.inspect} (expected #{v["out"].inspect})" if got != v["out"]
    end
    expect(failures).to be_empty,
      "#{vectors['model']}: #{failures.length}/#{vectors['vectors'].length} mismatched\n" +
      failures.first(3).join("\n")
  end
end
