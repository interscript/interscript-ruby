# frozen_string_literal: true

require "interscript/isc"

RSpec.describe "ISC ↔ YAML round-trip", type: :integration do
  def parse_isc(src, filename = "test.isc")
    tree = Interscript::Isc::Parser.parse(src, filename: filename)
    Interscript::Isc::DocumentBuilder.build(tree, filename: filename)
  end

  def round_trip(doc_hash)
    yaml = Interscript::Isc::YamlBridge.to_yaml(doc_hash)
    doc_back = Interscript::Isc::YamlBridge.from_yaml(yaml)
    isc = Interscript::Isc::Serializer.serialize(doc_back)
    parse_isc(isc, "round-trip.isc")
  end

  def comparable(hash)
    {
      system_code: hash[:systemCode],
      test_count: hash[:tests]&.size || 0,
      stage_count: hash[:stages]&.size || 0,
    }
  end

  it "round-trips a minimal map" do
    src = <<~ISC
      system "TEST:eng-Latn:Latn:2026" {

      metadata {
        authority_id test
        name "Test Map"
      }

      tests {
        "hello" -> "world"
      }

      stage main {
        parallel {
          sub "a" "b"
          sub "c" "d"
        }
      }
      }
    ISC
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    expect(comparable(doc1)).to eq(comparable(doc2))
    expect(doc2[:tests].size).to eq(1)
    expect(doc2[:stages].first[:body].first[:rules].size).to eq(2)
  end

  it "preserves StringValue items" do
    src = %(system "T:e-L:Latn:1" {\nstage main {\nsub "abc" "def"\n}\n})
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    rule = doc2[:stages].first[:body].first[:rule]
    expect(rule[:from]).to be_a(Interscript::Isc::Items::StringValue)
    expect(rule[:from].value).to eq("abc")
  end

  it "preserves Set items" do
    src = %(system "T:e-L:Latn:1" {\nstage main {\nsub any("abc") "x"\n}\n})
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    rule = doc2[:stages].first[:body].first[:rule]
    expect(rule[:from]).to be_a(Interscript::Isc::Items::Set)
    expect(rule[:from].chars).to eq(%w[a b c])
  end

  it "preserves Capture and CaptureRef items" do
    src = %(system "T:e-L:Latn:1" {\nstage main {\nsub capture("x") ref(1)\n}\n})
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    rule = doc2[:stages].first[:body].first[:rule]
    expect(rule[:from]).to be_a(Interscript::Isc::Items::CaptureGroup)
    expect(rule[:to]).to be_a(Interscript::Isc::Items::Capture)
  end

  it "preserves Concat items" do
    src = <<~ISC
      system "T:e-L:Latn:1" {
      stage main {
        sub {
          from "a" + "b"
          to "c"
        }
      }
      }
    ISC
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    rule = doc2[:stages].first[:body].first[:rule]
    expect(rule[:from]).to be_a(Interscript::Isc::Items::Concat)
  end

  it "preserves constraints" do
    src = <<~ISC
      system "T:e-L:Latn:1" {
      stage main {
        sub "a" "b"
          before "c"
          after "d"
      }
      }
    ISC
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    rule = doc2[:stages].first[:body].first[:rule]
    expect(rule[:constraints].size).to eq(2)
    expect(rule[:constraints].first[:kind]).to eq(:before)
  end

  it "preserves run directives" do
    src = %(system "T:e-L:Latn:1" {\nstage main {\nrun map.dep.stage.main\n}\n})
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    run_item = doc2[:stages].first[:body].first
    expect(run_item[:kind]).to eq(:run)
    expect(run_item[:dependency]).to eq("dep")
    expect(run_item[:stage]).to eq("main")
  end

  it "preserves compose and string_case directives" do
    src = <<~ISC
      system "T:e-L:Latn:1" {
      stage main {
        title_case
        compose
      }
      }
    ISC
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    items = doc2[:stages].first[:body]
    expect(items.map { |i| i[:kind] }).to include(:string_case, :compose)
  end

  it "preserves aliases" do
    src = <<~ISC
      system "T:e-L:Latn:1" {

      aliases {
        vowels = any("aeiou")
      }

      stage main {
        sub vowels "x"
      }
      }
    ISC
    doc1 = parse_isc(src)
    doc2 = round_trip(doc1)
    expect(doc2[:aliases].size).to eq(1)
    expect(doc2[:aliases].first[:name]).to eq("vowels")
    expect(doc2[:aliases].first[:value]).to be_a(Interscript::Isc::Items::Set)
  end

  it "round-trips real maps from /tmp/isc-verify" do
    maps_dir = "/tmp/isc-verify"
    skip "isc-verify not found" unless Dir.exist?(maps_dir)

    tested = 0
    failed = []

    Dir.glob("#{maps_dir}/*.isc").sort.first(20).each do |path|
      base = File.basename(path, ".isc")
      begin
        src = File.read(path)
        doc1 = parse_isc(src, base)
        doc2 = round_trip(doc1)
        # Verify structural equivalence
        expect(doc1[:tests].size).to eq(doc2[:tests].size)
        expect(doc1[:stages].size).to eq(doc2[:stages].size)
        tested += 1
      rescue => e
        failed << "#{base}: #{e.message[0..60]}"
      end
    end

    expect(failed).to be_empty, "#{failed.size}/#{tested} maps failed:\n#{failed.join("\n")}"
  end
end
