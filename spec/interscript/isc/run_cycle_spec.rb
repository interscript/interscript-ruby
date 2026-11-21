# frozen_string_literal: true

require "interscript"

# WO20 differential-fuzz finding (maps#294): a self-recursive
# `run stage.<self>` (or a mutual run cycle across stages) recursed until
# `SystemStackError` — a crash-class death embedders cannot meaningfully
# handle (rs aborted the process outright pre-0.3.3; ts overflowed its
# stack the same way). The cross-runtime contract: the run chain is
# threaded through stage execution and a revisited resolved target is a
# named `MapLogicError` carrying the chain, in the directive's own
# syntax — mirroring the W1 `use cycle:` named errors and rs's shipped
# 0.3.3 guard (py's conversion-time guard fires earlier still).
# A NON-cyclic re-run stays legal: the diamond pin below (two callers
# sharing one downstream run) must keep working.
RSpec.describe "fuzz: run cycles are named errors, never stack overflows" do
  let(:fixture_dir) { File.expand_path("../fixtures/fuzz", __dir__) }

  before do
    allow(Interscript).to receive(:load_path).and_return([fixture_dir])
    allow(Interscript).to receive(:map_aliases).and_return({})
  end

  it "names a self-recursive run stage.<self> (maps#294 repro)" do
    expect { Interscript.transliterate("self-run", "aa") }
      .to raise_error(Interscript::MapLogicError, /run cycle/)
  end

  it "names a mutual run cycle across stages" do
    expect { Interscript.transliterate("mutual-run", "x") }
      .to raise_error(Interscript::MapLogicError, /run cycle/)
  end

  it "still allows a non-cyclic diamond of shared runs" do
    expect(Interscript.transliterate("diamond-run", "ab1")).to eq("AB2")
  end
end
