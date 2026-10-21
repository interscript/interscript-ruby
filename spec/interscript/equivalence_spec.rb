# frozen_string_literal: true

require "json"
require "tmpdir"
require "interscript/equivalence"

RSpec.describe Interscript::Equivalence do
  def write_map(dir, name, body)
    path = File.join(dir, "#{name}.isc")
    File.write(path, body)
    path
  end

  def identical_pair(dir)
    body = <<~ISC
      system "TST:xx-Latn:Latn:1" {
        metadata {
          authority_id tst
          id 1
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        tests { "ab" ->  "ab" }
        stage main { parallel { sub "a" "a" } }
      }
    ISC
    [write_map(dir, "tst-a-1", body), write_map(dir, "tst-b-1", body.gsub("tst-a-1", "tst-b-1"))]
  end

  it "reports full agreement for identical systems" do
    Dir.mktmpdir do |dir|
      identical_pair(dir)
      Interscript.load_path.unshift(dir)
      begin
        result = described_class.check("tst-a-1", "tst-b-1", samples: ["ab", "abc", "b"])
        expect(result[:ratio]).to eq(1.0)
        expect(result[:distinguishing]).to be_empty
      ensure
        Interscript.load_path.delete(dir)
      end
    end
  end

  it "finds the minimal distinguishing sample for divergent systems" do
    Dir.mktmpdir do |dir|
      body_a = <<~ISC
        system "TST:xx-Latn:Latn:1" {
          metadata {
            authority_id tst
            id 1
            language iso-639-2:xx
            source_script Latn
            destination_script Latn
          }
          stage main { parallel { sub "a" "x" } }
        }
      ISC
      body_b = body_a.gsub('sub "a" "x"', 'sub "a" "y"').gsub("id 1", "id 2")
      write_map(dir, "tst-c-1", body_a)
      write_map(dir, "tst-c-2", body_b)
      Interscript.load_path.unshift(dir)
      begin
        result = described_class.check("tst-c-1", "tst-c-2", samples: ["a", "b"])
        expect(result[:ratio]).to eq(0.5)
        expect(result[:distinguishing]).to eq([{sample: "a", first: "x", second: "y"}])
      ensure
        Interscript.load_path.delete(dir)
      end
    end
  end
end
