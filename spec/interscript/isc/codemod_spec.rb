# frozen_string_literal: true

require "interscript/isc/codemod"

RSpec.describe Interscript::Isc::Codemod do
  let(:cm) { described_class.new(write: false) }

  def convert(imp_src)
    cm.convert(imp_src, filename: "test.imp")
  end

  it "converts basic metadata block" do
    imp = <<~IMP
      metadata {
        authority_id: test
        id: 2026
        name: "Test Map"
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("authority_id test")
    expect(isc).to include("id 2026")
    expect(isc).to include('name "Test Map"')
  end

  it "converts description heredoc to brace block" do
    imp = <<~IMP
      metadata {
        description: |
          Line 1
          Line 2
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("description {")
    expect(isc).to include("Line 1")
    expect(isc).to include("Line 2")
  end

  it "converts notes list to notes block" do
    imp = <<~IMP
      metadata {
        notes:
          - First note
          - Second note
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("notes {")
    expect(isc).to include("note")
    expect(isc).to include("First note")
  end

  it "converts test entries from comma to arrow" do
    imp = <<~IMP
      tests {
        test "hello", "world"
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("hello")
    expect(isc).to include("world")
    expect(isc).to include("->")
  end

  it "converts def_alias to assignment" do
    imp = <<~IMP
      aliases {
        def_alias my_alias, "abc"
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("my_alias")
    expect(isc).to include("=")
  end

  it "converts sub rule with arrow" do
    imp = <<~IMP
      stage {
        sub "a" => "b"
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("sub")
    expect(isc).not_to include("=>")
  end

  it "converts modifier kwargs (before:, after:)" do
    imp = <<~IMP
      stage {
        sub "a", "b", before: "c", after: "d"
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("before")
    expect(isc).to include("after")
    expect(isc).not_to include("before:")
  end

  it "converts separator kwarg" do
    imp = <<~IMP
      stage {
        separate separator: "-"
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("separate separator")
    expect(isc).not_to include("separator:")
  end

  it "escapes braces in description body" do
    imp = <<~IMP
      metadata {
        description: |
          Code: x = {1, 2}
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("\\{")
    expect(isc).to include("\\}")
  end

  it "preserves apostrophes in metadata values" do
    imp = <<~IMP
      metadata {
        name: "People's Republic"
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("People's Republic")
  end

  it "converts multi-line list values to brace blocks" do
    imp = <<~IMP
      metadata {
        notes:
          - First item
          - Second item
      }
    IMP
    isc = convert(imp)
    expect(isc).to include("{")
    expect(isc).to include("}")
  end
end