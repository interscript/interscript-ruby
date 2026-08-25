# frozen_string_literal: true

require "spec_helper"

RSpec.describe Interscript::Isc::Parser do
  let(:parser) { described_class.new }

  def parse(snippet)
    described_class.parse(snippet)
  rescue Interscript::Isc::ParseError => e
    raise e.cause || e
  end

  describe "minimal system" do
    it "parses an empty system block" do
      tree = parse(<<~ISC)
        system "BGN-PCGN:ukr-Cyrl:Latn:2019" {
        }
      ISC
      expect(tree.dig(:system, :system_code).to_s).to eq("BGN-PCGN:ukr-Cyrl:Latn:2019")
    end
  end

  describe "metadata" do
    it "parses basic metadata fields" do
      tree = parse(<<~ISC)
        system "BGN-PCGN:ukr-Cyrl:Latn:2019" {
          metadata {
            authority "BGN-PCGN"
            name "Romanization of Ukrainian (2019 Agreement)"
            system_status current
          }
        }
      ISC
      meta = tree[:system][:body].find { |b| b[:metadata] }[:metadata]
      fields = meta.map(&:keys).flatten
      expect(fields).to include(:authority, :name, :system_status)
    end

    it "parses description block" do
      tree = parse(<<~ISC)
        system "X:a-b:C-D:1" {
          metadata {
            description {
              This is a multi-line
              description.
            }
          }
        }
      ISC
      desc = tree[:system][:body].find { |b| b[:metadata] }[:metadata]
                          .find { |h| h[:description] }[:description]
      expect(desc.to_s).to include("multi-line")
    end
  end

  describe "aliases" do
    it "parses a simple alias" do
      tree = parse(<<~ISC)
        system "X:a-b:C-D:1" {
          aliases {
            vowel = any("aeiou")
          }
        }
      ISC
      aliases = tree[:system][:body].find { |b| b[:aliases] }[:aliases]
      expect(aliases.first[:name].to_s).to eq("vowel")
    end
  end

  describe "tests" do
    it "parses arrow-form tests" do
      tree = parse(<<~ISC)
        system "X:a-b:C-D:1" {
          tests {
            "Алушта" -> "Alushta"
            "Київ" -> "Kyiv"
          }
        }
      ISC
      tests = tree[:system][:body].find { |b| b[:tests] }[:tests]
      expect(tests.size).to eq(2)
      expect(tests.first[:input].to_s).to eq("Алушта")
      expect(tests.first[:expected].to_s).to eq("Alushta")
    end
  end

  describe "stages with compact rules" do
    it "parses a parallel block of compact sub rules" do
      tree = parse(<<~ISC)
        system "X:a-b:C-D:1" {
          stage main {
            parallel {
              sub "щ" "shch"
              sub "ь" "’" before any("аеєжиійоуяю")
            }
          }
        }
      ISC
      stage = tree[:system][:body].find { |b| b[:stage] }
      expect(stage[:stage_name].to_s).to eq("main")
      parallel = Array(stage[:stage]).find { |s| s[:parallel] }
      rules = Array(parallel[:parallel])
      expect(rules.size).to eq(2)
      expect(rules.first[:from]).to be_a(Hash)
    end
  end

  describe "dependencies" do
    it "parses dependency with alias" do
      tree = parse(<<~ISC)
        system "X:a-b:C-D:1" {
          dependency "UN:ukr-Cyrl:Latn:2012" as cyrllatn
        }
      ISC
      dep = tree[:system][:body].find { |b| b[:target] }
      expect(dep[:target].to_s).to eq("UN:ukr-Cyrl:Latn:2012")
      expect(dep[:alias].to_s).to eq("cyrllatn")
    end
  end

  describe "error handling" do
    it "raises ParseError on malformed input with filename context" do
      expect {
        described_class.parse(%(system "X" { broken ), filename: "test.isc")
      }.to raise_error(Interscript::Isc::ParseError, /test\.isc/)
    end
  end
end
