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

RSpec.describe "ISC semantics — contexts, maybe, capture" do
  def with_map(name, body)
    dir = Dir.mktmpdir
    File.write(File.join(dir, name), body)
    Interscript.load_path.unshift(dir)
    yield
  ensure
    Interscript.load_path.delete(dir) if dir
  end

  def context_map(id, rule)
    <<~ISC
      system "TST:xx-Latn:Latn:#{id}" {
        metadata {
          authority_id tst
          id #{id}
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        stage main { parallel { sub { #{rule} } } }
      }
    ISC
  end

  it "rules: before is a zero-width lookbehind (not consumed)" do
    with_map("tst-before-2.isc", context_map(11, 'from "a" to "X" before "b"')) do
      expect(Interscript.transliterate("tst-before-2", "ba")).to eq("bX")
      expect(Interscript.transliterate("tst-before-2", "ab")).to eq("ab")
    end
  end

  it "rules: after is a zero-width lookahead (not consumed)" do
    with_map("tst-after-2.isc", context_map(12, 'from "b" to "Y" after "a"')) do
      expect(Interscript.transliterate("tst-after-2", "ba")).to eq("Ya")
      expect(Interscript.transliterate("tst-after-2", "ab")).to eq("ab")
    end
  end

  it "rules: maybe is zero-or-one and participates in longest-match" do
    with_map("tst-maybe-2.isc", <<~ISC) do
      system "TST:xx-Latn:Latn:13" {
        metadata {
          authority_id tst
          id 13
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        stage main { parallel { sub { from "k" + maybe("h") to "X" } } }
      }
    ISC
      expect(Interscript.transliterate("tst-maybe-2", "k")).to eq("X")
      expect(Interscript.transliterate("tst-maybe-2", "kh")).to eq("X")
      expect(Interscript.transliterate("tst-maybe-2", "kk")).to eq("XX")
    end
  end

  it "rules: capture/ref round-trips in sequential rules" do
    with_map("tst-capseq-2.isc", <<~ISC) do
      system "TST:xx-Latn:Latn:14" {
        metadata {
          authority_id tst
          id 14
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        stage main { sub { from capture(any("0".."9")) to ref(1) } }
      }
    ISC
      expect(Interscript.transliterate("tst-capseq-2", "77a9")).to eq("77a9")
    end
  end

  it "rules: capture inside parallel is pending capture support (WO80)" do
    with_map("tst-cappar-1.isc", context_map(15, 'from capture(any("0".."9")) to ref(1)')) do
      expect { Interscript.transliterate("tst-cappar-1", "5") }
        .to raise_error(NoMethodError, /max_length/)
    end
  end
end
