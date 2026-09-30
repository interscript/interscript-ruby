# frozen_string_literal: true

require "interscript"
require "interscript/isc"

RSpec.describe Interscript::Isc::NodeAdapter do
  let(:parser) { Interscript::Isc::Parser.new }

  def parse_and_adapt(src)
    tree = parser.parse(src, filename: "test.isc")
    doc = Interscript::Isc::DocumentBuilder.build(tree, filename: "test.isc")
    described_class.to_interscript_node(doc)
  end

  describe ".to_interscript_node" do
    it "produces a Node::Document" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata {
            authority_id test
            name "Test"
          }
          stage main {
            sub "a" "b"
          }
        }
      ISC
      expect(node).to be_a(Interscript::Node::Document)
    end

    it "extracts metadata" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata {
            authority_id alalc
            id 1997
            name "Test Map"
          }
          stage main { }
        }
      ISC
      expect(node.metadata.data[:authority_id]).to eq("alalc")
      expect(node.metadata.data[:id]).to eq("1997")
      expect(node.metadata.data[:name]).to eq("Test Map")
    end

    it "extracts tests" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          tests {
            "hello" -> "world"
          }
          stage main { }
        }
      ISC
      expect(node.tests).to be_a(Interscript::Node::Tests)
      expect(node.tests.data.size).to eq(1)
      expect(node.tests.data[0][0]).to eq("hello")
      expect(node.tests.data[0][1]).to eq("world")
    end

    it "builds a main stage" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            sub "a" "b"
          }
        }
      ISC
      expect(node.stages).to have_key(:main)
      expect(node.stages[:main]).to be_a(Interscript::Node::Stage)
    end

    it "converts parallel blocks" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            parallel {
              sub "a" "b"
              sub "c" "d"
            }
          }
        }
      ISC
      stage = node.stages[:main]
      parallel = stage.children.find { |c| c.is_a?(Interscript::Node::Group::Parallel) }
      expect(parallel).not_to be_nil
      expect(parallel.children.size).to eq(2)
    end

    it "converts sub rules with from/to" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            sub "x" "y"
          }
        }
      ISC
      rule = node.stages[:main].children.first
      expect(rule).to be_a(Interscript::Node::Rule::Sub)
      expect(rule.from).to be_a(Interscript::Node::Item::String)
      expect(rule.to).to be_a(Interscript::Node::Item::String)
    end

    it "converts block-form sub rules" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            sub {
              from "a" + "b"
              to "c"
            }
          }
        }
      ISC
      rule = node.stages[:main].children.first
      expect(rule.from).to be_a(Interscript::Node::Item::String)
      expect(rule.to).to be_a(Interscript::Node::Item::String)
    end

    it "converts aliases" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          aliases {
            my_alias = "abc"
          }
          stage main {
            sub my_alias "x"
          }
        }
      ISC
      expect(node.aliases).to have_key(:my_alias)
      rule = node.stages[:main].children.first
      expect(rule.from).to be_a(Interscript::Node::Item::Alias)
    end

    it "converts capture and ref" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            sub capture("x") ref(1)
          }
        }
      ISC
      rule = node.stages[:main].children.first
      expect(rule.from).to be_a(Interscript::Node::Item::CaptureGroup)
      expect(rule.to).to be_a(Interscript::Node::Item::CaptureRef)
    end

    it "converts any() constructor" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            sub any("abc") "x"
          }
        }
      ISC
      rule = node.stages[:main].children.first
      expect(rule.from).to be_a(Interscript::Node::Item::Any)
    end

    it "converts boundary primitives" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            sub boundary "X"
          }
        }
      ISC
      rule = node.stages[:main].children.first
      expect(rule.from).to be_a(Interscript::Node::Item::Alias)
    end

    it "converts constraints" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            sub "a" "b"
              before "c"
              after "d"
          }
        }
      ISC
      rule = node.stages[:main].children.first
      expect(rule.before).to be_a(Interscript::Node::Item::String)
      expect(rule.after).to be_a(Interscript::Node::Item::String)
    end

    it "converts run directive" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            run map.dep.stage.main
          }
        }
      ISC
      run_rule = node.stages[:main].children.first
      expect(run_rule).to be_a(Interscript::Node::Rule::Run)
    end
  end

  describe "transliteration integration" do
    it "produces correct transliteration through the Node pipeline" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage main {
            parallel {
              sub "a" "b"
              sub "c" "d"
            }
          }
        }
      ISC
      interp = Interscript::Interpreter.new
      interp.compile(node)
      result = interp.call("acd")
      expect(result).to eq("bdd")
    end

    it "handles multi-stage pipelines" do
      node = parse_and_adapt(<<~ISC)
        system "TEST:eng-Latn:Latn:2026" {
          metadata { name "T" }
          stage first {
            sub "a" "b"
          }
          stage main {
            run stage.first
            sub "b" "c"
          }
        }
      ISC
      interp = Interscript::Interpreter.new
      interp.compile(node)
      result = interp.call("a")
      expect(result).to eq("c")
    end
  end
end

RSpec.describe "NodeAdapter document identity" do
  it "carries the system code into the document name" do
    tree = Interscript::Isc::Parser.parse(
      'system "X:a-b:C-D:1" { stage main { sub { from "a" to "b" } } }'
    )
    doc = Interscript::Isc::DocumentBuilder.build(tree)
    node = Interscript::Isc::NodeAdapter.to_interscript_node(doc)
    # The Ruby compiler registers compiled maps under Document#name; a
    # nil name registered them under "" and every transliterate call
    # crashed on nil.call.
    expect(node.name).to eq("X:a-b:C-D:1")
  end
end

RSpec.describe "NodeAdapter range handling" do
  it "keeps ISC ranges as native Any ranges — codepoint semantics, not string-succ expansion" do
    src = <<~ISC
      system "TEST:aze-Arab:Latn:2026" {
        metadata { name "T" }
        stage main {
          parallel { sub "q" "k" }
          sub { from any("a".."￿") to upcase before boundary }
        }
      }
    ISC
    node = Interscript::Isc::NodeAdapter.to_interscript_node(
      Interscript::Isc::DocumentBuilder.build(Interscript::Isc::Parser.parse(src))
    )
    upcase_rule = node.stages[:main].children
      .select { |c| c.is_a?(Interscript::Node::Rule::Sub) }
      .find { |r| r.to == :upcase }
    # A Ruby String range expands via String#succ (a, b, ..., z, aa, ab …)
    # which never reaches non-ASCII codepoints — the range must stay a range.
    expect(upcase_rule.from.value).to be_a(Range)
    interp = Interscript::Interpreter.new
    interp.compile(node)
    expect(interp.call("īş")).to eq("Īş")
  end
end

RSpec.describe "NodeAdapter any-list constraints" do
  it "keeps primitives as aliases, never their inspect" do
    tree = Interscript::Isc::Parser.parse(
      'system "x" { stage main { sub { from "ം" to "m" after any([boundary, "‌", "‍"]) } } }'
    )
    doc = Interscript::Isc::DocumentBuilder.build(tree)
    node = Interscript::Isc::NodeAdapter.to_interscript_node(doc)
    stage = Interscript::Interpreter::Stage.new(node, "")
    re = stage.send(:build_regexp, node.stages[:main].children.first)
    # The constraint must match boundary positions — an inspect leak
    # turns the lookahead into a garbage char class.
    expect(re).not_to include("Primitive")
    expect("പ്പം ഹ").to match(Regexp.new(re))
  end
end

RSpec.describe "NodeAdapter string escapes" do
  it "decodes escape sequences in test strings" do
    src = <<~'ISC'
      system "T:a-b:C-D:1" {
        metadata { name "T" }
        tests {
          "pod\"ezd" -> "p\"ezd"
          "a\tb\nc" -> "déjà"
        }
        stage main { sub "a" "b" }
      }
    ISC
    node = Interscript::Isc::NodeAdapter.to_interscript_node(
      Interscript::Isc::DocumentBuilder.build(Interscript::Isc::Parser.parse(src))
    )
    tests = node.tests.data
    expect(tests[0]).to eq(['pod"ezd', 'p"ezd'])
    expect(tests[1]).to eq(["a\tb\nc", "déjà"])
  end
end
