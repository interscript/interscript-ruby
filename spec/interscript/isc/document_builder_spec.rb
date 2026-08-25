# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::DocumentBuilder do
  let(:src) do
    <<~ISC
      system "TEST:eng-Latn:Latn:2026" {
        metadata {
          authority_id test
          id 2026
          language iso-639-2:eng
          source_script Latn
          destination_script Latn
          name "Test Map"
          creation_date 2026
          description { This is a test description. }
          notes {
            note "First note"
            note "Second note"
          }
        }

        tests {
          "hello" -> "hello"
          "world" -> "world"
        }

        stage main {
          sub "a" "b"
          sub "c" "d"
        }
      }
    ISC
  end

  describe ".build" do
    let(:doc) do
      tree = Interscript::Isc::Parser.parse(src, filename: "test.isc")
      described_class.build(tree, filename: "test.isc")
    end

    it "extracts metadata fields" do
      meta = doc[:metadata]
      expect(meta[:authority_id]).to eq("test")
      expect(meta[:id]).to eq("2026")
      expect(meta[:language]).to eq("iso-639-2:eng")
      expect(meta[:name]).to eq("Test Map")
      expect(meta[:creation_date]).to eq("2026")
    end

    it "extracts description with normalization" do
      expect(doc[:metadata][:description]).to include("test description")
    end

    it "extracts notes as strings" do
      notes = doc[:metadata][:notes]
      expect(notes).to be_an(Array)
      expect(notes.size).to eq(2)
      expect(notes[0]).to include("First note")
    end

    it "extracts tests" do
      expect(doc[:tests].size).to eq(2)
      expect(doc[:tests][0][:input]).to eq("hello")
      expect(doc[:tests][0][:expected]).to eq("hello")
    end

    it "extracts stage rules" do
      expect(doc[:stages].size).to eq(1)
      stage = doc[:stages].first
      expect(stage[:name]).to eq("main")
      expect(stage[:body].size).to eq(2)
    end

    it "filters noop rules from empty parallel blocks" do
      src_with_empty = <<~ISC
        system "TEST:eng-Latn:Latn:2026" {
          metadata {
            name "Test"
          }
          stage main {
            parallel {
              # just a comment
            }
            sub "a" "b"
          }
        }
      ISC
      tree = Interscript::Isc::Parser.parse(src_with_empty, filename: "t.isc")
      doc = described_class.build(tree, filename: "t.isc")
      parallel_items = doc[:stages].first[:body].select { |i| i[:kind] == :parallel }
      expect(parallel_items.first[:rules]).to be_empty
    end
  end

  describe "escaped braces in description" do
    it "unescapes braces in description body" do
      src = <<~ISC
        system "X:eng-Latn:Latn:2026" {
          metadata {
            description { Code has \\{x\\} braces. }
          }
          stage main {
          }
        }
      ISC
      tree = Interscript::Isc::Parser.parse(src, filename: "t.isc")
      doc = described_class.build(tree, filename: "t.isc")
      expect(doc[:metadata][:description]).to include("{x}")
    end
  end

  describe "heredoc normalization" do
    it "strips per-line indentation from description" do
      src = <<~ISC
        system "X:eng-Latn:Latn:2026" {
          metadata {
            description {
                Line one
                Line two
            }
          }
          stage main {
          }
        }
      ISC
      tree = Interscript::Isc::Parser.parse(src, filename: "t.isc")
      doc = described_class.build(tree, filename: "t.isc")
      desc = doc[:metadata][:description]
      expect(desc).to include("Line one")
      expect(desc).to include("Line two")
      expect(desc).not_to match(/^\s+/)
    end
  end
end