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

RSpec.describe "ISC semantics — run and to-directives" do
  def with_map(name, body)
    dir = Dir.mktmpdir
    File.write(File.join(dir, name), body)
    Interscript.load_path.unshift(dir)
    yield
  ensure
    Interscript.load_path.delete(dir) if dir
  end

  it "rules: run dispatches to a dependency-aliased cross-map stage" do
    lib = <<~ISC
      system "TST:xx-Latn:Latn:22" {
        metadata {
          authority_id tst
          id 22
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        stage main { parallel { sub "1" "one" } }
      }
    ISC
    runner = <<~ISC
      system "TST:xx-Latn:Latn:23" {
        metadata {
          authority_id tst
          id 23
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        dependency "tst-lib-1" as lib
        stage main {
          run map.lib.stage.main
          parallel { sub "2" "two" }
        }
      }
    ISC
    with_map("tst-lib-1.isc", lib) do
      with_map("tst-run-1.isc", runner) do
        expect(Interscript.transliterate("tst-run-1", "12")).to eq("onetwo")
      end
    end
  end

  it "rules: the to upcase directive is unimplemented in the ISC interpreter (WO80)" do
    # The corpus's rus map exercises `to upcase` via the legacy path; the
    # ISC executor raises on the directive for both literal and any-class
    # froms. IS-1 v2 must either specify the directive or scope it out
    # for the ISC engine (the A4 decision).
    with_map("tst-up-1.isc", <<~ISC) do
      system "TST:xx-Latn:Latn:21" {
        metadata {
          authority_id tst
          id 21
          language iso-639-2:xx
          source_script Latn
          destination_script Latn
        }
        stage main { parallel { sub { from any("a".."c") to upcase } } }
      }
    ISC
      expect { Interscript.transliterate("tst-up-1", "abc") }
        .to raise_error(NoMethodError, /nth_string/)
    end
  end
end

RSpec.describe "ISC semantics — funcall and stdlib" do
  def with_map(name, body)
    dir = Dir.mktmpdir
    File.write(File.join(dir, name), body)
    Interscript.load_path.unshift(dir)
    yield
  ensure
    Interscript.load_path.delete(dir) if dir
  end

  def system_map(id, body)
    <<~ISC
      system "TST:xx-Latn:Latn:#{id}" {
        metadata { authority_id tst; id #{id}; language iso-639-2:xx; source_script Latn; destination_script Latn }
        #{body}
      }
    ISC
  end

  it "rules: run <stdlib-name> dispatches the stdlib function" do
    with_map("tst-fn-1.isc", system_map(51, "stage main { run downcase }")) do
      expect(Interscript.transliterate("tst-fn-1", "AbC")).to eq("abc")
    end
  end

  it "rules: stage-level case directives run at their position, on the whole string" do
    with_map("tst-fn-2.isc", system_map(52,
      "stage main { downcase parallel { sub { from \"b\" to \"B\" } } }")) do
      # downcase applies before the sub (rule order), so b -> B still fires
      expect(Interscript.transliterate("tst-fn-2", "AB")).to eq("aB")
    end
  end

  it "rules: run accepts no kwargs — kwargs belong to declared funcall directives (rababa)" do
    with_map("tst-fn-3.isc", system_map(53, "stage main { run separate separator: \"-\" }")) do
      expect { Interscript.transliterate("tst-fn-3", "abc") }
        .to raise_error(Interscript::Isc::ParseError)
    end
  end

  it "rules: stray identifiers are consumed as no-ops — pinned as a hazard" do
    # HAZARD (A4 follow-up): `run nosuchfunction` drops BOTH identifiers
    # at parse time and the stage becomes empty — a typo'd map is
    # silently wrong. Ruled normative-for-now (legacy .imp corpus
    # tolerance, grammar/concerns/stages.rb comment_item); the stricter
    # parse is an open item tracked in the IS-1 v2 text, gated on a
    # clean parse of the full 293-map corpus across all three compilers.
    with_map("tst-fn-4.isc", system_map(54, "stage main { run nosuchfunction parallel { sub { from \"a\" to \"b\" } } }")) do
      expect(Interscript.transliterate("tst-fn-4", "a")).to eq("b")
    end
  end
end

RSpec.describe "ISC semantics — item algebra and boundary" do
  def with_map(name, body)
    dir = Dir.mktmpdir
    File.write(File.join(dir, name), body)
    Interscript.load_path.unshift(dir)
    yield
  ensure
    Interscript.load_path.delete(dir) if dir
  end

  def system_map(id, body)
    <<~ISC
      system "TST:xx-Latn:Latn:#{id}" {
        metadata { authority_id tst; id #{id}; language iso-639-2:xx; source_script Latn; destination_script Latn }
        #{body}
      }
    ISC
  end

  it "rules: any(<chars>) is a character set of length 1" do
    with_map("tst-item-1.isc", system_map(61,
      "stage main { parallel { sub { from any(\"bc\") to \"X\" } } }")) do
      expect(Interscript.transliterate("tst-item-1", "abcd")).to eq("aXXd")
    end
  end

  it "rules: any(<lo>..<hi>) is an inclusive codepoint range" do
    with_map("tst-item-2.isc", system_map(62,
      "stage main { parallel { sub { from any(\"0\"..\"9\") to \"N\" } } }")) do
      expect(Interscript.transliterate("tst-item-2", "a7b")).to eq("aNb")
    end
  end

  it "rules: capture + ref substitutes the captured source text" do
    with_map("tst-item-3.isc", system_map(63,
      "stage main { sequence { sub { from capture(\"a\") + \"b\" to ref(1) + \"Y\" } } }")) do
      expect(Interscript.transliterate("tst-item-3", "ab")).to eq("aY")
    end
  end

  it "rules: boundary is a zero-width word-edge, not string-edge-only" do
    with_map("tst-item-4.isc", system_map(64,
      "stage main { parallel { sub { from \"a\" to \"X\" after boundary } } }")) do
      # string end IS a word edge
      expect(Interscript.transliterate("tst-item-4", "xa")).to eq("xX")
      # mid-word: no edge after a
      expect(Interscript.transliterate("tst-item-4", "ab")).to eq("ab")
    end
  end
end

RSpec.describe "ISC semantics — metadata contract and embedded tests" do
  def with_map(name, body)
    dir = Dir.mktmpdir
    File.write(File.join(dir, name), body)
    Interscript.load_path.unshift(dir)
    yield
  ensure
    Interscript.load_path.delete(dir) if dir
  end

  it "rules: embedded tests are normative data — never executed by transliterate" do
    dir = Dir.mktmpdir
    File.write(File.join(dir, "tst-test-1.isc"), <<~ISC)
      system "TST:xx-Latn:Latn:71" {
        metadata { authority_id tst; id 71; language iso-639-2:xx; source_script Latn; destination_script Latn }
        stage main { parallel { sub { from "a" to "b" } } }
        tests { "zzz" -> "wrong" }
      }
    ISC
    Interscript.load_path.unshift(dir)
    # a deliberately wrong expectation does not fire; the verification
    # layer (conformance runner / artifact build) executes tests
    expect(Interscript.transliterate("tst-test-1", "a")).to eq("b")
  ensure
    Interscript.load_path.delete(dir) if dir
  end
end
