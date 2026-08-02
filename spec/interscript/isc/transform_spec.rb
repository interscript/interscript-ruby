# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::Transform do
  it "transforms a quoted string to StringValue" do
    tree = { string: { simple: "hello" } }
    result = described_class.new.apply(tree)
    expect(result).to be_a(Interscript::Isc::Items::StringValue)
    expect(result.value).to eq("hello")
  end

  it "transforms escape sequences" do
    tree = { string: { sequence: [{ char: "a" }, { newline: "n" }, { char: "b" }] } }
    result = described_class.new.apply(tree)
    expect(result.value).to eq("a\nb")
  end

  it "transforms unicode escapes" do
    tree = { string: { sequence: [{ unicode: "00e9" }] } }
    result = described_class.new.apply(tree)
    expect(result.value).to eq("é")
  end

  it "transforms none to Items::None" do
    tree = { none: { simple: nil } }
    result = described_class.new.apply(tree)
    expect(result).to be_a(Interscript::Isc::Items::None)
  end

  it "transforms zero-width primitives" do
    %w[boundary line_start line_end word_boundary space non_boundary].each do |prim|
      tree = { primitive: { simple: prim } }
      result = described_class.new.apply(tree)
      expect(result).to be_a(Interscript::Isc::Items::Primitive)
      expect(result.name).to eq(prim)
    end
  end

  it "transforms alias references" do
    tree = { alias: { simple: "my_alias" } }
    result = described_class.new.apply(tree)
    expect(result).to be_a(Interscript::Isc::Items::AliasRef)
    expect(result.name).to eq("my_alias")
  end

  it "transforms capture references" do
    tree = { ref: { digit: { simple: "3" } } }
    result = described_class.new.apply(tree)
    expect(result).to be_a(Interscript::Isc::Items::Capture)
    expect(result.index).to eq(3)
  end

  it "transforms capture groups" do
    tree = { capture_inner: { string: { simple: "x" } } }
    result = described_class.new.apply(tree)
    expect(result).to be_a(Interscript::Isc::Items::CaptureGroup)
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