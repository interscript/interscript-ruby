# frozen_string_literal: true

require "interscript/isc"
require "interscript"

# ISC-WF-1 unit specs: the four new constructs at the parser/builder
# layer (spec docs/isc-wf-1.md §2).
RSpec.describe "ISC-WF-1 grammar" do
  def parse_doc(src, filename = "wf1.isc")
    tree = Interscript::Isc::Parser.parse(src, filename: filename)
    Interscript::Isc::DocumentBuilder.build(tree, filename: filename)
  end

  describe "W3 languages declaration" do
    it "parses space-separated languages in the system block" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          languages rus bel ukr
          stage main { sub "a" "b" }
        }
      ISC
      expect(doc[:languages]).to eq(%w[rus bel ukr])
    end

    it "parses comma-separated languages" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          languages rus, bel, ukr
          stage main { sub "a" "b" }
        }
      ISC
      expect(doc[:languages]).to eq(%w[rus bel ukr])
    end

    it "keeps a single language" do
      doc = parse_doc(%(system "T:e-L:Latn:1" {\nlanguages kur\nstage main { sub "a" "b" }\n}\n))
      expect(doc[:languages]).to eq(%w[kur])
    end

    it "stops the language list at the next block item" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          languages rus bel
          stage main {
            sub "a" "b"
          }
        }
      ISC
      expect(doc[:languages]).to eq(%w[rus bel])
      expect(doc[:stages].size).to eq(1)
    end

    it "omits the languages key on maps without the declaration" do
      doc = parse_doc(%(system "T:e-L:Latn:1" {\nstage main { sub "a" "b" }\n}\n))
      expect(doc).not_to have_key(:languages)
    end
  end

  describe "W1 ruleset declaration" do
    it "parses a ruleset block at map top level" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          ruleset leading {
            parallel {
              sub "a" "b"
            }
            sub "c" "d"
          }
          stage main { sub "e" "f" }
        }
      ISC
      expect(doc[:rulesets].size).to eq(1)
      rs = doc[:rulesets].first
      expect(rs[:name]).to eq("leading")
      expect(rs[:body].map { |i| i[:kind] }).to eq(%i[parallel bare_rule])
      expect(rs[:body].first[:rules].size).to eq(1)
    end

    it "keeps rulesets out of the stages list" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          ruleset r { sub "a" "b" }
          stage main { sub "c" "d" }
        }
      ISC
      expect(doc[:stages].map { |s| s[:name] }).to eq(%w[main])
      expect(doc[:rulesets].map { |r| r[:name] }).to eq(%w[r])
    end

    it "rejects stray identifiers in stage bodies as before" do
      src = %(system "T:e-L:Latn:1" {\nstage main {\n  bogus_token\n}\n}\n)
      expect { Interscript::Isc::Parser.parse(src) }.to raise_error(Interscript::Isc::ParseError)
    end
  end

  describe "W1/W2 use directive" do
    it "parses a plain same-map reference" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          stage main {
            use leading
            sub "a" "b"
          }
        }
      ISC
      item = doc[:stages].first[:body].first
      expect(item[:kind]).to eq(:use)
      expect(item[:ruleset]).to eq("leading")
      expect(item[:dependency]).to be_nil
      expect(item).not_to have_key(:overrides)
    end

    it "parses a dependency-qualified reference" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          stage main {
            use shared.leading
          }
        }
      ISC
      item = doc[:stages].first[:body].first
      expect(item[:ruleset]).to eq("leading")
      expect(item[:dependency]).to eq("shared")
    end

    it "parses an override block with replacement rows" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          stage main {
            use leading override {
              sub "ะ" "a"
              sub "ิ" "yy" when tha
            }
          }
        }
      ISC
      item = doc[:stages].first[:body].first
      expect(item[:overrides].size).to eq(2)
      expect(item[:overrides].first[:from]).to eq(Interscript::Isc::Items::StringValue.new("ะ"))
      expect(item[:overrides].first[:when_languages]).to be_nil
      expect(item[:overrides].last[:when_languages]).to eq(%w[tha])
    end

    it "keeps the override as part of the use directive (one site)" do
      # An override block with no preceding use must not parse.
      src = %(system "T:e-L:Latn:1" {\nstage main {\n  override {\n    sub "a" "b"\n  }\n}\n}\n)
      expect { Interscript::Isc::Parser.parse(src) }.to raise_error(Interscript::Isc::ParseError)
    end
  end

  describe "W3 when guard" do
    it "parses a single-language guard on a compact rule" do
      doc = parse_doc(%(system "T:e-L:Latn:1" {\nstage main {\nsub "ҫ" "ș" when chv\n}\n}\n))
      rule = doc[:stages].first[:body].first[:rule]
      expect(rule[:when_languages]).to eq(%w[chv])
    end

    it "parses a multi-language guard" do
      doc = parse_doc(%(system "T:e-L:Latn:1" {\nstage main {\nsub "a" "b" when rus, bel\n}\n}\n))
      rule = doc[:stages].first[:body].first[:rule]
      expect(rule[:when_languages]).to eq(%w[rus bel])
    end

    it "parses a guard after constraints" do
      doc = parse_doc(%(system "T:e-L:Latn:1" {\nstage main {\nsub "a" "b" not_before "x" when kur\n}\n}\n))
      rule = doc[:stages].first[:body].first[:rule]
      expect(rule[:constraints].first[:kind]).to eq(:not_before)
      expect(rule[:when_languages]).to eq(%w[kur])
    end

    it "parses a guard in block form" do
      doc = parse_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          stage main {
            sub {
              from "a"
              to "b"
              when kur
            }
          }
        }
      ISC
      rule = doc[:stages].first[:body].first[:rule]
      expect(rule[:when_languages]).to eq(%w[kur])
    end

    it "omits when_languages on unguarded rules" do
      doc = parse_doc(%(system "T:e-L:Latn:1" {\nstage main {\nsub "a" "b"\n}\n}\n))
      rule = doc[:stages].first[:body].first[:rule]
      expect(rule).not_to have_key(:when_languages)
    end
  end
end
