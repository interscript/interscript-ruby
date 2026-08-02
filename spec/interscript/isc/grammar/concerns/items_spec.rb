# frozen_string_literal: true

require "interscript/isc"

RSpec.describe Interscript::Isc::Grammar::Concerns::Items do
  let(:parser) { Interscript::Isc::Parser.new }

  it "parses quoted string atom" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub "abc", "def"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses single-quoted string atom" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub 'abc', 'def'
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses none atom" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub none, "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses zero-width primitives" do
    primitives = %w[boundary line_start line_end word_boundary space non_boundary]
    primitives.each do |prim|
      tree = parser.parse(<<~ISC, filename: "t.isc")
        system "X:e-Latn:Latn:1" {
          stage main {
            sub #{prim}, "X"
          }
        }
      ISC
      expect(tree[:system][:body]).to be_an(Array), "failed for primitive: #{prim}"
    end
  end

  it "parses any_character atom" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub any_character, "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses any() constructor with string arg" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub any("abc"), "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses any() constructor with set arg" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub any(["a", "b", "c"]), "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses any() constructor with range arg" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub any("a".."z"), "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses any() constructor with alias arg" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub any(my_alias), "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses any() with zero-width primitives (space+line_end)" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub {
            from any(space+line_end)
            to "X"
          }
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses capture() constructor" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub capture("abc"), "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses maybe() constructor" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub maybe("a"), "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses some() constructor" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub some("a"), "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses ref(N) capture reference" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub capture("a"), ref(1)
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses function call (upcase, downcase, title_case)" do
    %w[upcase downcase title_case].each do |fn|
      tree = parser.parse(<<~ISC, filename: "t.isc")
        system "X:e-Latn:Latn:1" {
          stage main {
            sub "a", #{fn}
          }
        }
      ISC
      expect(tree[:system][:body]).to be_an(Array), "failed for function: #{fn}"
    end
  end

  it "parses concatenation with +" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub "a" + "b", "c"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses concatenation with whitespace" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        stage main {
          sub "a" "b", "c"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end

  it "parses alias reference" do
    tree = parser.parse(<<~ISC, filename: "t.isc")
      system "X:e-Latn:Latn:1" {
        aliases {
          my_alias = "abc"
        }
        stage main {
          sub my_alias, "X"
        }
      }
    ISC
    expect(tree[:system][:body]).to be_an(Array)
  end
end