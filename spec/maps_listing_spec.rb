# frozen_string_literal: true

# Interscript.maps must see the ISC corpus — the Detector and the
# transliterate-each-map suites enumerate systems through it, and it
# still globbed only the legacy .imp extension.
require "spec_helper"

MAPS = ENV.fetch("INTERSCRIPT_MAPS_PATH", "../maps/maps")
LIBS = ENV.fetch("INTERSCRIPT_MAPS_LIBS", File.expand_path("../libs", MAPS))

RSpec.describe "Interscript.maps" do
  def with_load_path(dir)
    dir = File.expand_path(dir)
    added = Interscript.load_path.first != dir
    Interscript.load_path.unshift(dir) if added
    yield
  ensure
    Interscript.load_path.delete_at(0) if added
  end

  it "lists ISC system maps" do
    skip "maps checkout not present" unless File.file?(File.expand_path("bgnpcgn-ukr-Cyrl-Latn-2019.isc", MAPS))

    with_load_path(MAPS) do
      expect(Interscript.maps(basename: false, load_path: true))
        .to include(File.expand_path("bgnpcgn-ukr-Cyrl-Latn-2019.isc", File.expand_path(MAPS)))
    end
  end

  it "lists ISC library maps" do
    skip "maps checkout not present" unless File.file?(File.expand_path("posix.isc", LIBS))

    with_load_path(LIBS) do
      expect(Interscript.maps(basename: false, load_path: true, libraries: true))
        .to include(File.expand_path("posix.isc", File.expand_path(LIBS)))
    end
  end
end

RSpec.describe "Interscript.parse on ISC libraries" do
  it "dispatches .isc to the ISC parser, not the .imp DSL" do
    libs = File.expand_path(ENV.fetch("INTERSCRIPT_MAPS_LIBS", "../libs"))
    skip "maps checkout not present" unless File.file?(File.expand_path("posix.isc", libs))

    added = Interscript.load_path.first != libs
    Interscript.load_path.unshift(libs) if added
    begin
      doc = Interscript.parse("posix")
      expect(doc).to be_a(Interscript::Node::Document)
      expect(doc.aliases.keys).to include(:upper)
    ensure
      Interscript.load_path.delete_at(0) if added
    end
  end
end

RSpec.describe "Interscript.parse caching for ISC documents" do
  it "returns the cached document — repeated parses must not re-run the ISC parser" do
    maps = File.expand_path(MAPS)
    skip "maps checkout not present" unless File.file?(File.expand_path("alalc-aze-Arab-Latn-1997.isc", maps))

    added = Interscript.load_path.first != maps
    Interscript.load_path.unshift(maps) if added
    begin
      first = Interscript.parse("alalc-aze-Arab-Latn-1997")
      second = Interscript.parse("alalc-aze-Arab-Latn-1997")
      expect(first.equal?(second)).to be(true)
    ensure
      Interscript.load_path.delete_at(0) if added
    end
  end
end

RSpec.describe "Compiler.call on ISC maps" do
  it "reuses the cached document — repeated calls must not re-run the ISC parser" do
    maps = File.expand_path(MAPS)
    skip "maps checkout not present" unless File.file?(File.expand_path("alalc-aze-Arab-Latn-1997.isc", maps))

    added = Interscript.load_path.first != maps
    Interscript.load_path.unshift(maps) if added
    begin
      a = Interscript::Interpreter.call("alalc-aze-Arab-Latn-1997")
      b = Interscript::Interpreter.call("alalc-aze-Arab-Latn-1997")
      expect(a.map.equal?(b.map)).to be(true)
    ensure
      Interscript.load_path.delete_at(0) if added
    end
  end
end
