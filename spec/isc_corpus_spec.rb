# frozen_string_literal: true

# The ISC-corpus regression gate (TODO.impl 12): the runtime must
# transliterate through cross-map runs from .isc documents — the path
# the NodeAdapter used to drop entirely.
require "interscript"

MAPS = ENV.fetch("INTERSCRIPT_MAPS_PATH", "../maps/maps")

RSpec.describe "the ISC corpus" do
  before(:all) do
    Interscript.load_path.unshift(MAPS) unless Interscript.load_path.first == MAPS
  end

  it "transliterates through a dependency run (bgnpcgn-ukr -> Anton Olehovych)" do
    skip "maps checkout not present" unless File.file?(File.expand_path("bgnpcgn-ukr-Cyrl-Latn-2019.isc", MAPS))

    expect(Interscript.transliterate("bgnpcgn-ukr-Cyrl-Latn-2019", "Антон Олегович"))
      .to eq("Anton Olehovych")
  end

  it "transliterates the library-dependent German map (Tschüß! -> Tschueß!)" do
    skip "maps checkout not present" unless File.file?(File.expand_path("bgnpcgn-deu-Latn-Latn-2000.isc", MAPS))

    expect(Interscript.transliterate("bgnpcgn-deu-Latn-Latn-2000", "Tschüß!"))
      .to eq("Tschueß!")
  end
end
