# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::Grammar::Concerns::Metadata do
  let(:parser) { Interscript::Isc::Parser.new }

  # Helper: wrap metadata in a system block so the parser can accept it
  def wrap_metadata(meta_src)
    <<~ISC
      system "TEST:eng-Latn:Latn:2026" {
        #{meta_src}
        stage main { }
      }
    ISC
  end

  it "parses minimal metadata" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        authority_id test
        id 2026
        language iso-639-2:eng
        source_script Latn
        destination_script Latn
        name "Test"
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses description as braced block" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        description { This is a description. }
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses notes with multiple entries" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        notes {
          note "First"
          note "Second"
        }
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses notes with empty list" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        notes { }
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses generic field with value" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        custom_field value
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses generic field with heredoc value" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        custom_field { |
          Heredoc body line 1
          Heredoc body line 2
        }
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses empty field (no value)" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        empty_field
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses relations block" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        relations {
          based_on "OTHER:eng-Latn:Latn:2020"
        }
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "handles escaped braces in raw text" do
    tree = parser.parse(wrap_metadata(<<~META), filename: "t.isc")
      metadata {
        description { This has \\{escaped\\} braces. }
      }
    META
    expect(tree[:system][:body]).to be_an(Array)
  end
end
