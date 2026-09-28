# frozen_string_literal: true

# Interscript.maps must see the ISC corpus — the Detector and the
# transliterate-each-map suites enumerate systems through it, and it
# still globbed only the legacy .imp extension.
require "spec_helper"

RSpec.describe "Interscript.maps" do
  MAPS = ENV.fetch("INTERSCRIPT_MAPS_PATH", "../maps/maps")
  LIBS = ENV.fetch("INTERSCRIPT_MAPS_LIBS", File.expand_path("../libs", MAPS))

  it "lists ISC system maps" do
    skip "maps checkout not present" unless File.file?(File.expand_path("bgnpcgn-ukr-Cyrl-Latn-2019.isc", MAPS))

    dir = File.expand_path(MAPS)
    Interscript.load_path.unshift(dir) unless Interscript.load_path.first == dir
    expect(Interscript.maps(basename: false, load_path: true))
      .to include(File.expand_path("bgnpcgn-ukr-Cyrl-Latn-2019.isc", dir))
  end

  it "lists ISC library maps" do
    skip "maps checkout not present" unless File.file?(File.expand_path("posix.isc", LIBS))

    dir = File.expand_path(LIBS)
    Interscript.load_path.unshift(dir) unless Interscript.load_path.first == dir
    expect(Interscript.maps(basename: false, load_path: true, libraries: true))
      .to include(File.expand_path("posix.isc", dir))
  end
end
