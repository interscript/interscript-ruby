# frozen_string_literal: true

require "interscript/isc"
require "interscript"

# ISC-WF-1 round-trip specs: the new constructs survive
# parse → builder → YAML bridge → serializer → re-parse (spec docs/
# isc-wf-1.md §2; the existing round-trip suite stays green untouched).
RSpec.describe "ISC-WF-1 round trip" do
  def parse_isc(src, filename = "wf1.isc")
    tree = Interscript::Isc::Parser.parse(src, filename: filename)
    Interscript::Isc::DocumentBuilder.build(tree, filename: filename)
  end

  def round_trip(doc_hash)
    yaml = Interscript::Isc::YamlBridge.to_yaml(doc_hash)
    doc_back = Interscript::Isc::YamlBridge.from_yaml(yaml)
    isc = Interscript::Isc::Serializer.serialize(doc_back)
    parse_isc(isc, "round-trip.isc")
  end

  it "round-trips languages, rulesets, use-with-override and when guards" do
    src = <<~ISC
      system "T:rus-Cyrl:Latn:9" {
        languages kur ckv
        ruleset leading {
          parallel {
            sub "қ" "ķ"
            sub "ҫ" "ș" when ckv
          }
        }
        stage main {
          use leading override {
            sub "қ" "k" when kur
          }
          parallel {
            sub "б" "b"
          }
        }
      }
    ISC
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)

    expect(doc2[:languages]).to eq(%w[kur ckv])
    expect(doc2[:rulesets].size).to eq(1)
    expect(doc2[:rulesets].first[:name]).to eq("leading")
    expect(doc2[:stages].first[:body].first[:kind]).to eq(:use)
    expect(doc2[:stages].first[:body].first[:ruleset]).to eq("leading")
    expect(doc2[:stages].first[:body].first[:overrides].size).to eq(1)
    expect(doc2[:stages].first[:body].first[:overrides].first[:when_languages]).to eq(%w[kur])
    ruleset_rule = doc2[:rulesets].first[:body].first[:rules].last
    expect(ruleset_rule[:when_languages]).to eq(%w[ckv])
    expect(doc1[:languages]).to eq(doc2[:languages])
    expect(doc1[:rulesets]).to eq(doc2[:rulesets])
    expect(doc1[:stages]).to eq(doc2[:stages])
  end

  it "keeps pre-WF1 documents free of the new keys" do
    src = %(system "T:e-L:Latn:1" {\nstage main {\nsub "a" "b"\n}\n}\n)
    doc = round_trip(parse_isc(src))
    expect(doc).not_to have_key(:languages)
    expect(doc).not_to have_key(:rulesets)
  end
end
