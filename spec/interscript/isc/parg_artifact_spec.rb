# frozen_string_literal: true

# Differential gate: every corpus map parses byte-identically through
# the shipped .parg artifact and the Ruby-DSL grammar. The runtime
# prefers the artifact; this spec is the proof the two agree.
require "support/parg_diff"

RSpec.describe Interscript::Isc::Parser, :aggregate_failures do
  maps_dir = ENV.fetch("INTERSCRIPT_MAPS_PATH", "../maps/maps")
  maps = Dir[File.expand_path("*.isc", maps_dir)].sort

  skip "maps checkout not present" if maps.empty?
  skip "parsanol lacks PARG (needs >= 1.3.61)" unless Interscript::Isc::Parser.respond_to?(:artifact)

  it "parses every corpus map identically via artifact and DSL" do
    failures = []

    maps.each do |path|
      source = File.read(path, encoding: "utf-8")
      artifact_tree = PargDiff.normalize(
        Interscript::Isc::Normalizer.normalize(described_class.parse_with_artifact(source))
      )
      dsl_tree = PargDiff.normalize(
        Interscript::Isc::Normalizer.normalize(described_class.parse_with_dsl(source))
      )
      diffs = PargDiff.diff(dsl_tree, artifact_tree)
      failures << "#{File.basename(path)}: #{diffs.first(3).join("; ")}" unless diffs.empty?
    rescue Parsanol::ParseFailed => e
      failures << "#{File.basename(path)}: parse failed: #{e.message[0, 120]}"
    end

    expect(failures).to be_empty,
      "#{failures.size}/#{maps.size} maps diverge; first: #{failures.first(5).join(" | ")}"
  end
end
