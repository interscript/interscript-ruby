# frozen_string_literal: true

# JsonIR must serialise to the production corpus shape: a document
# carries only its own aliases (dependency and library aliases resolve
# at runtime via the alias `map:` qualifier), and any()-sets serialise
# as {kind: "any", of: [...]} — never as merged library dumps or
# char-class rewrites.
require "interscript"
require "json"

MAPS = ENV.fetch("INTERSCRIPT_MAPS_PATH", "../maps/maps")

RSpec.describe "Interscript::Compiler::JsonIR serialisation form" do
  before(:all) do
    Interscript.load_path.unshift(MAPS) unless Interscript.load_path.first == MAPS
  end

  it "serialises only the document's own aliases" do
    skip "maps checkout not present" unless File.file?(File.expand_path("un-tam-Taml-Latn-1972.isc", MAPS))

    doc = Interscript::Compiler.parse_isc(File.expand_path("un-tam-Taml-Latn-1972.isc", MAPS))
    ir = JSON.parse(Interscript::Compiler::JsonIR.new.compile(doc).code)

    expect(ir["aliases"].keys).to eq(["taml_chars_1"])
  end

  it "serialises any()-sets as any/of string alternatives" do
    skip "maps checkout not present" unless File.file?(File.expand_path("un-tam-Taml-Latn-1972.isc", MAPS))

    doc = Interscript::Compiler.parse_isc(File.expand_path("un-tam-Taml-Latn-1972.isc", MAPS))
    ir = JSON.parse(Interscript::Compiler::JsonIR.new.compile(doc).code)
    alias_def = ir["aliases"]["taml_chars_1"]

    expect(alias_def["kind"]).to eq("any")
    expect(alias_def["of"]).to all(include("kind" => "string"))
  end
end
