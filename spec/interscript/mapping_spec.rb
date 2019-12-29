require "spec_helper"
require "interscript/mapping"

RSpec.describe Interscript::Mapping do
  describe ".for" do
    context "with a valid system code" do
      it "returns a serialize system mappings" do
        system_code = "un-ben-Beng-Latn-2016"
        mapping = Interscript::Mapping.for(system_code)

        expect(mapping.rules).to be_empty
        expect(mapping.characters["অ"]).to eq("a")
        expect(mapping.name).to eq("Bengali Romanization, Version 4.0")
      end
    end

    context "with valid and extened system" do
      it "returns system mappings with extended rules" do
        system_code = "alalc-ben-Beng-Latn-2017"

        mapping = Interscript::Mapping.for(system_code)
        extended = Interscript::Mapping.for("un-ben-Beng-Latn-2016")

        expect(mapping.rules).to be_empty
        expect(mapping.characters["অ"]).to eq("a")
        expect(mapping.characters["য"]).to eq("ya")
        expect(mapping.name).to eq("Bengali Romanization, 2017")
        expect(mapping.characters.count).to be >= extended.characters.count
      end
    end

    context "with a invalid system code" do
      it "raise an ruby exception without any mappings" do
        invalid_system_code = "lets-make-up-a-system-code"

        expect do
          Interscript::Mapping.for(invalid_system_code)
        end.to raise_error(Interscript::InvalidSystemError)
      end
    end
  end
end
