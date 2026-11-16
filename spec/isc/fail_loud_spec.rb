# frozen_string_literal: true

# WO18 G4/G8 — fail-loud + funcall parity from the merged four-runtime
# audit (maps docs/parity/README.md).
#
# G4: requesting a stage the map doesn't have used to crash with a
# NoMethodError (accidental nil dereference through execute_rule).
# Canon (rs) is a named MapLogicError at both sites — the requested
# main stage and a run's target stage.
#
# G8: the ISC surface includes the upcase/reverse/strip/swapcase fn
# literals (grammar `fn_lit` / stage directives); ruby's
# Stdlib::Functions was missing all four, so the `upcase` directive
# crashed with NoMethodError. ts/py/rs semantics are the reference.

require "tmpdir"
require "fileutils"

RSpec.describe "WO18 — interpreter fail-loud behavior" do
  def with_map(name, body)
    dir = Dir.mktmpdir
    File.write(File.join(dir, name), body)
    Interscript.load_path.unshift(dir)
    yield
  ensure
    Interscript.load_path.delete(dir) if dir
  end

  describe "G4 — missing stage" do
    it "requesting an absent stage raises MapLogicError (was: NoMethodError)" do
      with_map("tst-g4-main.isc", <<~ISC) do
        system "T:tst-g4-main:1" {
          stage main { sub "a" "b" }
        }
      ISC
        interp = Interscript::Interpreter.call("tst-g4-main")
        expect { interp.call("abc", :mahn) }.to raise_error(
          Interscript::MapLogicError,
          /stage "mahn" not found/
        )
      end
    end

    it "running an absent stage target raises MapLogicError (was: NoMethodError)" do
      with_map("tst-g4-run.isc", <<~ISC) do
        system "T:tst-g4-run:1" {
          stage main { run stage.nope }
        }
      ISC
        interp = Interscript::Interpreter.call("tst-g4-run")
        expect { interp.call("abc", :main) }.to raise_error(
          Interscript::MapLogicError,
          /stage "nope" not found/
        )
      end
    end

    it "a present stage still executes" do
      with_map("tst-g4-ok.isc", <<~ISC) do
        system "T:tst-g4-ok:1" {
          stage main { sub "a" "b" }
        }
      ISC
        expect(Interscript::Interpreter.call("tst-g4-ok").call("abc", :main)).to eq("bbc")
      end
    end
  end

  describe "G8 — fn literals execute (the audit's probe shapes)" do
    it "the upcase stage directive runs (probe tst-upcase-exec)" do
      with_map("tst-wo18-upcase.isc", <<~ISC) do
        # P15: upcase funcall execution (ruby Stdlib::Functions had no upcase).
        system "T:tst-wo18-upcase:1" {
          stage main {
            parallel { sub "§" " " }
            upcase
          }
        }
      ISC
        expect(Interscript.transliterate("tst-wo18-upcase", "§abc")).to eq(" ABC")
      end
    end

    it "reverse/strip/swapcase dispatch through the Funcall path" do
      # reverse/strip/swapcase are fn literals (`to` position) in the ISC
      # grammar — not stage directives — so the executable surface is the
      # Funcall rule; the legacy DSL builds one per available_function.
      expect(stage { reverse }.call("abc")).to eq("cba")
      expect(stage { strip }.call("  a b  ")).to eq("a b")
      expect(stage { swapcase }.call("aBc")).to eq("AbC")
    end
  end

  describe "WO20 fuzz — interscript-ruby#864: ref(N) constant-lookup crash" do
    # The fuzz campaign's 14 crash cases: `ref(N)` anywhere in an ISC map
    # crashed with NameError: uninitialized constant
    # Node::Item::CaptureRef — the item class exists (item/capture.rb,
    # next to CaptureGroup) but had no autoload entry, so the constant
    # resolved only when an earlier dependency parse happened to touch
    # CaptureGroup first. Corpus maps escaped by that accident.
    #
    # The named convention is the G8 one: an invalid from-position item
    # gets a parse-time MapLogicError (fn-literal-in-from → "Wrong type
    # Symbol" via try_convert). The capture-ref flavor is scoping-aware:
    # a ref whose capture group the from expression never opens is the
    # named rejection; PAIRED refs (the geminate idiom
    # `capture(any_character) + ref(1)`, pinned by node_adapter_spec)
    # and `to`-position refs (27 corpus maps) stay legal.

    def fresh_process_parse(map_name, map_body)
      lib = File.expand_path("../../lib", __dir__)
      dir = Dir.mktmpdir
      File.write(File.join(dir, "#{map_name}.isc"), map_body)
      script = "require \"interscript\"; " \
               "puts \"AUTOLOAD=\" + (Interscript::Node::Item.autoload?(:CaptureRef) || \"nil\").to_s; " \
               "Interscript.load_path.unshift(ARGV[0]); " \
               "begin; Interscript.parse(ARGV[1]); puts \"PARSE OK\"; " \
               "rescue Exception => e; puts e.class.to_s + \": \" + e.message; end"
      IO.popen([RbConfig.ruby, "-I", lib, "-e", script, dir, map_name], &:read)
    ensure
      FileUtils.remove_entry(dir) if dir
    end

    it "an unpaired capture ref in from position raises the named MapLogicError (was: NameError)" do
      # The campaign's minimized repro (fuzz findings/ruby-ref-in-from-crash).
      with_map("tst-wo20-ref-from.isc", <<~ISC) do
        system "T:tst-wo20-ref-from:1" {
          stage main {
            sequence {
              sub {
                from some(any(["k", "q"])) + ref(1)
                to "W" + ref(1)
              }
            }
          }
        }
      ISC
        expect { Interscript.parse("tst-wo20-ref-from") }.to raise_error(
          Interscript::MapLogicError,
          /ref\(1\) in from position has no matching capture group/
        )
      end
    end

    it "a capture ref nested in a from expression is rejected too" do
      with_map("tst-wo20-ref-from-nested.isc", <<~ISC) do
        system "T:tst-wo20-ref-from-nested:1" {
          stage main {
            sequence {
              sub {
                from some(ref(1))
                to "W"
              }
            }
          }
        }
      ISC
        expect { Interscript.parse("tst-wo20-ref-from-nested") }.to raise_error(
          Interscript::MapLogicError,
          /ref\(1\) in from position has no matching capture group/
        )
      end
    end

    it "a paired ref in from stays legal (the geminate idiom)" do
      # Scoping pin: the named rejection targets UNPAIRED refs only.
      # `from capture(any_character) + ref(1)` compiles to X(X)→X and is
      # pinned executable by node_adapter_spec; parsing it must never
      # hit the gate.
      with_map("tst-wo20-ref-paired.isc", <<~ISC) do
        system "T:tst-wo20-ref-paired:1" {
          stage main {
            sequence {
              sub {
                from capture(any_character) + ref(1)
                to ref(1)
              }
            }
          }
        }
      ISC
        expect { Interscript.parse("tst-wo20-ref-paired") }.not_to raise_error
        expect(Interscript.transliterate("tst-wo20-ref-paired", "чч")).to eq("ч")
      end
    end

    it "CaptureRef resolves by name — the autoload entry, not parse-order accident" do
      # Root cause pin, in a fresh process: autoload? is only observable
      # before the first resolution, so an in-process assertion here
      # would be order-dependent on the rest of the suite.
      out = fresh_process_parse("tst-wo20-autoload-probe", <<~ISC)
        system "T:tst-wo20-autoload-probe:1" {
          stage main { sub "a" "b" }
        }
      ISC
      expect(out).to include("AUTOLOAD=interscript/node/item/capture")
    end

    it "the issue repro in a fresh process: MapLogicError, never NameError" do
      out = fresh_process_parse("tst-wo20-fz-em8", <<~ISC)
        system "T:fz-em8:1" {
          stage main {
            sequence {
              sub {
                from some(any(["k", "q"])) + ref(1)
                to "W" + ref(1)
              }
            }
          }
        }
      ISC
      expect(out).to include("Interscript::MapLogicError")
      expect(out).not_to include("NameError")
    end

    it "a to-position ref parses and runs as a backreference (was: the same NameError)" do
      with_map("tst-wo20-ref-to.isc", <<~ISC) do
        system "T:tst-wo20-ref-to:1" {
          stage main {
            sequence {
              sub {
                from capture("k")
                to "W" + ref(1)
              }
            }
          }
        }
      ISC
        doc = Interscript.parse("tst-wo20-ref-to")
        expect(doc.stages[:main]).not_to be_nil
        expect(Interscript.transliterate("tst-wo20-ref-to", "kk")).to eq("WkWk")
      end
    end

    it "a to-position ref parses in a fresh process (order-independent)" do
      out = fresh_process_parse("tst-wo20-ref-to-fresh", <<~ISC)
        system "T:tst-wo20-ref-to-fresh:1" {
          stage main {
            sequence {
              sub {
                from capture("k")
                to "W" + ref(1)
              }
            }
          }
        }
      ISC
      expect(out).to include("PARSE OK")
      expect(out).not_to include("NameError")
    end
  end
end
