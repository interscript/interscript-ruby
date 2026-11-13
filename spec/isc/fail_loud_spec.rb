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
end
