# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::Grammar::Concerns::Metadata do
  let(:parser) { Interscript::Isc::Parser.new }

  it "parses minimal metadata" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        authority_id test
        id 2026
        language iso-639-2:eng
        source_script Latn
        destination_script Latn
        name "Test"
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "parses description as braced block" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        description { This is a description. }
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "parses notes with multiple entries" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        notes {
          note "First"
          note "Second"
        }
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "parses notes with empty list" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        notes { }
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "parses generic field with value" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        custom_field value
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "parses generic field with heredoc value" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        custom_field |
          Heredoc body line 1
          Heredoc body line 2
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "parses empty field (no value)" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        empty_field
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "parses multi-line unquoted text value" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        notes_body First line.
          Second line.
          Third line.
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "parses relations block" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        relations {
          based_on "OTHER:eng-Latn:Latn:2020"
          supersedes "OLD:eng-Latn:Latn:2010" note "replaces old version"
        }
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end

  it "handles escaped braces in raw text" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      metadata {
        description { This has \\{escaped\\} braces. }
      }
    ISC
    expect(tree[:metadata]).to be_a(Hash)
  end
end