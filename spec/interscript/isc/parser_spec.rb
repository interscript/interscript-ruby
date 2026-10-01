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
            "hello" -> "hello"
          }

          stage main {
            sub "a" "b"
          }
        }
      ISC
      tree = described_class.parse(src, filename: "test.isc")
      doc = Interscript::Isc::DocumentBuilder.build(tree, filename: "test.isc")
      expect(doc[:systemCode]).to include("TEST")
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

  describe "artifact runtime" do
    let(:src) do
      <<~ISC
        system "s" {
          metadata { authority_id t }
          stage main {
            parallel {
              sub "a" "b"
            }
          }
        }
      ISC
    end

    it "parses through the shipped .parg artifact when parsanol has PARG" do
      skip "parsanol lacks PARG (needs >= 1.3.61)" unless Interscript::Isc::Parser.respond_to?(:artifact)

      tree = described_class.parse(src)
      doc = Interscript::Isc::DocumentBuilder.build(tree, filename: "test.isc")
      expect(doc[:systemCode]).to eq("s")
      expect(doc[:tests]).to be_empty
    end

    it "produces byte-identical trees via artifact and DSL paths" do
      skip "parsanol lacks PARG (needs >= 1.3.61)" unless Interscript::Isc::Parser.respond_to?(:artifact)

      artifact_tree = described_class.parse_with_artifact(src)
      dsl_tree = described_class.parse_with_dsl(src)
      expect(artifact_tree).to eq(dsl_tree)
    end

    it "falls back to the DSL grammar when the artifact cannot load" do
      skip "parsanol lacks PARG (needs >= 1.3.61)" unless Interscript::Isc::Parser.respond_to?(:artifact)

      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(%r{isc\.artifact\.json}).and_raise(Errno::ENOENT)
      described_class.reset_artifact
      tree = described_class.parse(src)
      doc = Interscript::Isc::DocumentBuilder.build(tree, filename: "test.isc")
      expect(doc[:systemCode]).to eq("s")
      described_class.reset_artifact
    end
  end
end
