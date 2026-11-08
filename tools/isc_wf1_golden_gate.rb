#!/usr/bin/env ruby
# frozen_string_literal: true

# ISC-WF-1 additivity gate (spec §7). Re-runs the golden capture through
# the Ruby runtime and reports the delta — against a saved pre-change
# capture (--baseline) and against the interscript-rs golden out fields
# (--parity). Rows whose map adopts WF1 constructs are exempt from the
# gate (the non-adopting set must be byte-stable).
#
#   ruby tools/isc_wf1_golden_gate.rb \
#     --golden /path/to/interscript-rs/tests/golden/isc-wf0.jsonl \
#     --maps-root /path/to/interscript/maps \
#     --baseline /path/to/pre-change-ruby.jsonl --parity
#
# Exit status is non-zero when a gated delta is found.

require "json" # standard:disable Lint/RedundantRequireStatement (not preloaded outside bundler)
require "optparse"
require "yaml"
require "interscript"

options = {
  golden: "tests/golden/isc-wf0.jsonl",
  maps_root: ENV["ISC_MAPS_ROOT"] || "../maps"
}
OptionParser.new do |o|
  o.on("--golden PATH") { |v| options[:golden] = v }
  o.on("--maps-root PATH") { |v| options[:maps_root] = v }
  o.on("--baseline PATH", "compare against a saved pre-change capture") { |v| options[:baseline] = v }
  o.on("--parity", "also compare against the golden 'out' fields") { |v| options[:parity] = true }
end.parse!(ARGV)

# The rubygems index is not assumed to work here; wire the registry in
# process by reopening Interscript with plain methods (no
# instance_variable access) — the proven bundler bypass.
maps_root = File.expand_path(options[:maps_root])
maps_yaml = File.join(maps_root, "interscript-maps.yaml")
module Interscript
  class << self
    def gate_map_gems(yaml_path)
      @map_gems = {yaml_path => YAML.load_file(yaml_path)}
    end

    def gate_map_locations
      @map_locations = map_gems.flat_map do |i, v|
        Array(v["paths"]).map { |j| File.expand_path(j, File.dirname(i)) }
      end
    end

    def gate_map_aliases
      @map_aliases = {}
    end
  end
end
Interscript.gate_map_gems(maps_yaml)
Interscript.gate_map_locations
Interscript.gate_map_aliases

# Adopting maps (spec §7): rows of maps whose source uses WF1 constructs
# are exempt from the zero-delta requirement. The corpus has none at
# adoption time; the list lives next to the golden capture
# (interscript-rs tests/golden/adopting-maps.txt) once the first pilot
# lands.
adopting_path = File.join(File.dirname(options[:golden]), "adopting-maps.txt")
adopting = if File.exist?(adopting_path)
  File.readlines(adopting_path, encoding: "UTF-8")
    .reject { |l| l.start_with?("#") || l.strip.empty? }
    .map(&:strip).to_set
else
  Set.new
end

rows = File.readlines(options[:golden], encoding: "UTF-8").map { |l| JSON.parse(l) }
captured = rows.map do |row|
  out = begin
    Interscript.transliterate(row["map"], row["src"])
  rescue StandardError, NotImplementedError => e
    "ERROR:#{e.class}:#{e.message.lines.first.to_s.strip[0, 160]}"
  end
  {map: row["map"], src: row["src"], out: out, golden: row["out"]}
end

baseline = options[:baseline] &&
  File.readlines(options[:baseline], encoding: "UTF-8").map { |l| JSON.parse(l) }

gated = captured.reject { |r| adopting.include?(r[:map]) }
delta_vs_baseline = baseline && gated.zip(baseline).reject { |(g, b)| g[:out] == b["out"] }
delta_vs_golden = gated.reject { |r| r[:out] == r[:golden] }

puts "rows: #{captured.size} (gate: #{gated.size}, adopting-exempt: #{captured.size - gated.size})"
if baseline
  puts "delta vs baseline: #{delta_vs_baseline.size}"
  delta_vs_baseline.first(10).each do |(g, b)|
    puts "  #{g[:map]} #{g[:src].inspect}: baseline=#{b["out"].inspect} now=#{g[:out].inspect}"
  end
end
if options[:parity]
  puts "delta vs golden (cross-runtime): #{delta_vs_golden.size}"
  delta_vs_golden.first(10).each do |r|
    puts "  #{r[:map]} #{r[:src].inspect}: golden=#{r[:golden].inspect} ruby=#{r[:out].inspect}"
  end
end

failed = (delta_vs_baseline || []).any? || (options[:parity] ? delta_vs_golden.any? : false)
exit(failed ? 1 : 0)
