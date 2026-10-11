require "spec_helper"
require "interscript/ml/imf"

RSpec.describe Interscript::ML::IMF do
  describe ".first_alternates" do
    it "keeps the primary choice per token" do
      expect(described_class.first_alternates("وِكَالَةُ/وِكَالَةُ اَلْأَرْصَادِ")).to eq("وِكَالَةُ اَلْأَرْصَادِ")
    end

    it "leaves plain text untouched" do
      expect(described_class.first_alternates("مرحبا بالعالم")).to eq("مرحبا بالعالم")
    end

    it "handles edges" do
      expect(described_class.first_alternates("")).to eq("")
      expect(described_class.first_alternates("a/b c/d")).to eq("a c")
    end
  end
end
