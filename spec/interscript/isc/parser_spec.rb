# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::Parser do
  describe ".parse" do
    it "parses a minimal system block" do
      src = <<~ISC
        system "TEST:eng-Latn:Latn:2026" {
          metadata {
            authority_id test
            id 2026
            language iso-639-2:eng
            source_script Latn
            destination_script Latn
            name "Test Map"
          }

          tests {
            test "hello", "hello"
          }

          stage main {
            sub "a", "b"
          }
        }
      ISC
      tree = described_class.parse(src, filename: "test.isc")
      expect(tree).to be_a(Hash)
      expect(tree[:system][:system_code].to_s).to include("TEST")
    end

    it "raises ParseError on invalid syntax" do
      expect {
        described_class.parse("not isc content", filename: "bad.isc")
      }.to raise_error(Interscript::Isc::ParseError)
    end

    it "accepts empty metadata block" do
      src = <<~ISC
        system "TEST:eng-Latn:Latn:2026" {
          metadata {
          }
          stage main {
          }
        }
      ISC
      expect { described_class.parse(src, filename: "test.isc") }.not_to raise_error
    end
  end
end