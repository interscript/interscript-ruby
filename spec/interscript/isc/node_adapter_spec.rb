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
