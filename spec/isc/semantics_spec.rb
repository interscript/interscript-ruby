# frozen_string_literal: true

# WO80/A4 — normative rulings for the ISC semantic surface. Each vector
# pins the reference behavior; IS-1 v2 documents these as normative
# sections (the spec text accretes one section per ruled point).

require "tmpdir"

RSpec.describe "ISC semantics — parallel composition" do
  def with_map(name, body)
    dir = Dir.mktmpdir
    File.write(File.join(dir, name), body)
    Interscript.load_path.unshift(dir)
    yield
  ensure
    Interscript.load_path.delete(dir) if dir
  end

  it "rules: a parallel block is single-pass longest-match" do
    with_map("tst-long-1.isc", <<~ISC) do
      system "TST:xx-Latn:Latn:1" {
        metadata {
          authority_id tst
          id 1
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        stage main { parallel {
          sub "b" "Y"
          sub "ab" "X"
        } }
      }
    ISC
      expect(Interscript.transliterate("tst-long-1", "ab")).to eq("X")
    end
  end

  it "rules: duplicate rules in a parallel resolve last-declared-wins" do
    with_map("tst-tie-1.isc", <<~ISC) do
      system "TST:xx-Latn:Latn:2" {
        metadata {
          authority_id tst
          id 2
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        stage main { parallel {
          sub "a" "1"
          sub "a" "2"
        } }
      }
    ISC
      expect(Interscript.transliterate("tst-tie-1", "a")).to eq("2")
    end
  end
end
