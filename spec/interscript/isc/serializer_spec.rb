# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::Serializer, type: :integration do
  def serialize_and_parse(src)
    tree = Interscript::Isc::Parser.parse(src, filename: "t.isc")
    doc = Interscript::Isc::DocumentBuilder.build(tree, filename: "t.isc")
    isc = Interscript::Isc::Serializer.serialize(doc)
    tree2 = Interscript::Isc::Parser.parse(isc, filename: "rt.isc")
    Interscript::Isc::DocumentBuilder.build(tree2, filename: "rt.isc")
  end

  it "serializes a minimal system" do
    src = %(system "T:e-L:Latn:1" {\n\nmetadata {\n  name "Test"\n}\n\nstage main {\n  sub "a" "b"\n}\n})
    doc = serialize_and_parse(src)
    expect(doc[:systemCode]).to eq("T:e-L:Latn:1")
    expect(doc[:metadata][:name]).to eq("Test")
  end

  it "serializes Set items as single string" do
    src = %(system "T:e-L:Latn:1" {\nstage main {\nsub any("abc") "x"\n}\n})
    doc = serialize_and_parse(src)
    rule = doc[:stages].first[:body].first[:rule]
    expect(rule[:from]).to be_a(Interscript::Isc::Items::Set)
    expect(rule[:from].chars).to eq(%w[a b c])
  end

  it "serializes Concat items in block form" do
    src = %(system "T:e-L:Latn:1" {\nstage main {\nsub {\nfrom "a" + "b"\nto "c"\n}\n}\n})
    doc = serialize_and_parse(src)
    rule = doc[:stages].first[:body].first[:rule]
    expect(rule[:from]).to be_a(Interscript::Isc::Items::Concat)
  end

  it "serializes capture and ref" do
    src = %(system "T:e-L:Latn:1" {\nstage main {\nsub capture("x") ref(1)\n}\n})
    doc = serialize_and_parse(src)
    rule = doc[:stages].first[:body].first[:rule]
    expect(rule[:from]).to be_a(Interscript::Isc::Items::CaptureGroup)
    expect(rule[:to]).to be_a(Interscript::Isc::Items::Capture)
  end

  it "serializes dependencies without comma" do
    src = %(system "T:e-L:Latn:1" {\n\ndependency "dep-map" as dep\n\nstage main {\n  run map.dep.stage.main\n}\n})
    doc = serialize_and_parse(src)
    expect(doc[:dependencies].first[:target]).to eq("dep-map")
    expect(doc[:dependencies].first[:alias]).to eq("dep")
  end

  it "serializes compose and string_case directives" do
    src = %(system "T:e-L:Latn:1" {\n\nstage main {\n  title_case\n  compose\n}\n})
    doc = serialize_and_parse(src)
    kinds = doc[:stages].first[:body].map { |i| i[:kind] }
    expect(kinds).to include(:string_case, :compose)
  end

  it "serializes run directives" do
    src = %(system "T:e-L:Latn:1" {\n\nstage main {\n  run map.dep.stage.main\n}\n})
    doc = serialize_and_parse(src)
    run = doc[:stages].first[:body].first
    expect(run[:kind]).to eq(:run)
    expect(run[:dependency]).to eq("dep")
  end

  it "serializes parallel blocks" do
    src = %(system "T:e-L:Latn:1" {\n\nstage main {\n  parallel {\n    sub "a" "b"\n    sub "c" "d"\n  }\n}\n})
    doc = serialize_and_parse(src)
    parallel = doc[:stages].first[:body].first
    expect(parallel[:kind]).to eq(:parallel)
    expect(parallel[:rules].size).to eq(2)
  end
end
