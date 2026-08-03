# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::Transform do
  let(:parser) { Interscript::Isc::Parser.new }

  def parse_item(src)
    tree = parser.parse(src, filename: "t.isc")
    doc = Interscript::Isc::DocumentBuilder.build(tree, filename: "t.isc")
    stage = doc[:stages].first
    rule = stage[:body].first[:rule] || stage[:body].first[:rules]&.first
    rule
  end

  it "transforms a quoted string to StringValue" do
    rule = parse_item(<<~ISC)
      system "X:eng-Latn:Latn:1" {
        metadata { name "T" }
        stage main { sub "hello" "world" }
      }
    ISC
    expect(rule[:from]).to be_a(Interscript::Isc::Items::StringValue)
    expect(rule[:from].value).to eq("hello")
    expect(rule[:to].value).to eq("world")
  end

  it "transforms escape sequences in strings" do
    rule = parse_item(<<~ISC)
      system "X:eng-Latn:Latn:1" {
        metadata { name "T" }
        stage main { sub "a\\nb" "c" }
      }
    ISC
    expect(rule[:from].value).to eq("a\nb")
  end

  it "transforms unicode escapes" do
    rule = parse_item(<<~ISC)
      system "X:eng-Latn:Latn:1" {
        metadata { name "T" }
        stage main { sub "\\u00e9" "e" }
      }
    ISC
    expect(rule[:from].value).to eq("é")
  end

  it "transforms none to Items::None" do
    rule = parse_item(<<~ISC)
      system "X:eng-Latn:Latn:1" {
        metadata { name "T" }
        stage main { sub none "X" }
      }
    ISC
    expect(rule[:from]).to be_a(Interscript::Isc::Items::None)
  end

  it "transforms zero-width primitives" do
    %w[boundary line_start line_end word_boundary space non_boundary].each do |prim|
      rule = parse_item(<<~ISC)
        system "X:eng-Latn:Latn:1" {
          metadata { name "T" }
          stage main { sub #{prim} "X" }
        }
      ISC
      expect(rule[:from]).to be_a(Interscript::Isc::Items::Primitive),
             "expected Primitive for #{prim}, got #{rule[:from].class}"
      expect(rule[:from].name).to eq(prim)
    end
  end

  it "transforms alias references" do
    rule = parse_item(<<~ISC)
      system "X:eng-Latn:Latn:1" {
        metadata { name "T" }
        aliases {
          my_alias = "abc"
        }
        stage main { sub my_alias "X" }
      }
    ISC
    expect(rule[:from]).to be_a(Interscript::Isc::Items::AliasRef)
    expect(rule[:from].name).to eq("my_alias")
  end

  it "transforms capture references" do
    rule = parse_item(<<~ISC)
      system "X:eng-Latn:Latn:1" {
        metadata { name "T" }
        stage main { sub capture("a") ref(1) }
      }
    ISC
    expect(rule[:to]).to be_a(Interscript::Isc::Items::Capture)
    expect(rule[:to].index).to eq(1)
  end

  it "transforms capture groups" do
    rule = parse_item(<<~ISC)
      system "X:eng-Latn:Latn:1" {
        metadata { name "T" }
        stage main { sub capture("x") "y" }
      }
    ISC
    expect(rule[:from]).to be_a(Interscript::Isc::Items::CaptureGroup)
  end
end

RSpec.describe Interscript::Isc::Items do
  describe "StringValue" do
    it "stores a string value" do
      item = described_class::StringValue.new("hello")
      expect(item.value).to eq("hello")
    end
  end

  describe "None" do
    it "represents absence of value" do
      item = described_class::None.new
      expect(item).to be_a(described_class::None)
    end
  end

  describe "Primitive" do
    it "stores a primitive name" do
      item = described_class::Primitive.new("boundary")
      expect(item.name).to eq("boundary")
    end
  end

  describe "AliasRef" do
    it "stores an alias name" do
      item = described_class::AliasRef.new("my_alias")
      expect(item.name).to eq("my_alias")
    end
  end

  describe "Capture" do
    it "stores a capture group index" do
      item = described_class::Capture.new(2)
      expect(item.index).to eq(2)
    end
  end
end
