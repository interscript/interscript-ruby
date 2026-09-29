# frozen_string_literal: true

# Generator round-trip: every document the DSL can build must survive a
# generate → parse → adapt cycle with identical runtime behavior. This
# is the contract the Python bridge relies on — the rewritten python
# runtime executes ISC sources, so in-memory documents cross the
# boundary as generated ISC text.
require "spec_helper"

RSpec.describe Interscript::Isc::Generator do
  def round_trip(doc)
    isc = described_class.generate(doc)
    tree = Interscript::Isc::Parser.parse(isc)
    built = Interscript::Isc::DocumentBuilder.build(tree)
    Interscript::Isc::NodeAdapter.to_interscript_node(built)
  end

  def round_trip_stage(&block)
    original = stage(&block)
    reparsed = round_trip(original)
    [original, reparsed]
  end

  it "generates parseable ISC for a stage document" do
    doc = stage { sub "b", "e" }
    isc = described_class.generate(doc)
    expect(isc).to start_with(%(system "example-))
    expect { Interscript::Isc::Parser.parse(isc) }.not_to raise_error
  end

  it "round-trips basic substitution" do
    original, reparsed = round_trip_stage { sub "b", "e" }
    expect(reparsed.call("abcd")).to eq(original.call("abcd"))
  end

  it "round-trips substitution with all four constraints" do
    original, reparsed = round_trip_stage {
      sub "a", "A", before: space
      sub "a", "B", not_before: space
      sub "a", "C", after: space
      sub "a", "D", not_after: space
    }
    expect(reparsed.call("abcda abcda abada")).to eq(original.call("abcda abcda abada"))
  end

  it "round-trips a casing target" do
    original, reparsed = round_trip_stage { sub "b", :upcase }
    expect(reparsed.call("aba")).to eq(original.call("aba"))
  end

  it "round-trips parallel blocks" do
    original, reparsed = round_trip_stage {
      parallel {
        sub "ab", "X"
        sub "a", "Y"
      }
    }
    expect(reparsed.call("aba")).to eq(original.call("aba"))
  end

  it "round-trips any() sets and ranges" do
    original, reparsed = round_trip_stage {
      sub any("abc"), "X"
      sub "z", "W", before: any("aeiou")
    }
    expect(reparsed.call("zaza zab")).to eq(original.call("zaza zab"))
  end

  it "round-trips capture groups and references" do
    original, reparsed = round_trip_stage {
      sub capture("b") + capture("c"), ref(2) + ref(1)
    }
    expect(reparsed.call("xbc")).to eq(original.call("xbc"))
  end

  it "round-trips document-level aliases" do
    original = document {
      aliases do
        def_alias :vowel, any("aeiou")
      end
      stage {
        sub "v", "V", before: vowel
      }
    }
    reparsed = round_trip(original)
    expect(reparsed.call("ava eve")).to eq(original.call("ava eve"))
  end

  it "round-trips multiple stages with a stage run" do
    original = document {
      stage :first do
        sub "b", "e"
      end
      stage {
        run Interscript::Node::Item::Stage.new(:first)
      }
    }
    reparsed = round_trip(original)
    expect(reparsed.call("abcd")).to eq(original.call("abcd"))
  end
end
