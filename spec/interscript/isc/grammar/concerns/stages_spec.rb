# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::Grammar::Concerns::Stages do
  let(:parser) { Interscript::Isc::Parser.new }

  it "parses compact sub rule" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
          sub "a", "b"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses block-form sub rule with from/to" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
          sub {
            from "a" + "b"
            to "c"
          }
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses parallel block" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
          parallel {
            sub "a", "b"
            sub "c", "d"
          }
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses sequence block" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
          sequence {
            sub "a", "b"
            sub "c", "d"
          }
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses constraints (before, after, not_before, not_after)" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
          sub "a", "b"
            before "c"
            after "d"
            not_before "e"
            not_after "f"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses separate directive" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
          separate separator "-"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses compose directive" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
          compose
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses string_case directives" do
    %w[downcase upcase title_case].each do |op|
      tree = parser.parse(<<~ISC, filename: "t.isc")
        system "X:eng-Latn:Latn:2026" {
          stage main {
            #{op}
          }
        }
      ISC
      expect(tree[:system][:body]).to be_an(Array)
    end
  end

  it "parses run directive to dependency stage" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
          run map.dep.stage.main
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses empty stage block" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:eng-Latn:Latn:2026" {
        stage main {
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end
end