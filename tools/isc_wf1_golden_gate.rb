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
# --reverse replays the WO20 reverse-mode golden (isc-reverse.jsonl)
# instead: every row runs through the REVERSED document (parse, `#reverse`,
# `Interpreter.call(rdoc)`), byte-identically to the rs capture. The
# reverse golden has no adopting-set exemption — it was captured once
# and must replay identically everywhere; an execution error replays
# as `null`, the canonical marker the rs capture records.
#
# Exit status is non-zero when a gated delta is found.

require "json" # standard:disable Lint/RedundantRequireStatement (not preloaded outside bundler)
require "optparse"
require "yaml"
require "interscript"

options = {
  golden: "tests/golden/isc-wf0.jsonl",
  maps_root: ENV["ISC_MAPS_ROOT"] || "../maps",
  reverse: false
}
OptionParser.new do |o|
  o.on("--golden PATH") { |v| options[:golden] = v }
  o.on("--maps-root PATH") { |v| options[:maps_root] = v }
  o.on("--baseline PATH", "compare against a saved pre-change capture") { |v| options[:baseline] = v }
  o.on("--parity", "also compare against the golden 'out' fields") { |v| options[:parity] = true }
  o.on("--reverse", "replay the reverse-mode golden (isc-reverse.jsonl)") { |v| options[:reverse] = true }
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

    def gate_map_locations(locations = nil)
      @map_locations = locations || map_gems.flat_map do |i, v|
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

# The reverse golden covers the rs reverse fixtures too
# (tests/reverse_maps, siblings of the golden file): append them AFTER
# the corpus so a corpus map shadows a same-named fixture exactly like
# the rs capture's load path.
if options[:reverse]
  fixtures = File.expand_path(File.join(File.dirname(options[:golden]), "..", "reverse_maps"))
  if File.directory?(fixtures)
    Interscript.gate_map_locations(
      [File.join(maps_root, "maps"), File.join(maps_root, "libs"), fixtures]
    )
  end
end

# Adopting maps (spec §7): rows of maps whose source uses WF1 constructs
# are exempt from the zero-delta requirement. The corpus has none at
# adoption time; the list lives next to the golden capture
# (interscript-rs tests/golden/adopting-maps.txt) once the first pilot
# lands. The reverse golden has no exemption: captured once, replayed
# identically, no adoption flow.
adopting_path = File.join(File.dirname(options[:golden]), "adopting-maps.txt")
adopting = if options[:reverse]
  Set.new
elsif File.exist?(adopting_path)
  File.readlines(adopting_path, encoding: "UTF-8")
    .reject { |l| l.start_with?("#") || l.strip.empty? }
    .map(&:strip).to_set
else
  Set.new
end

# Missing golden = missing sibling checkout: skip like the rs/ts/py
# gates do instead of crashing (the reverse golden lands on rs main
# with the WO20 branch; until then this gate is a no-op).
unless File.exist?(options[:golden])
  puts "skip: no golden capture at #{options[:golden]}"
  exit 0
end

rows = File.readlines(options[:golden], encoding: "UTF-8").map { |l| JSON.parse(l) }
captured = rows.map do |row|
  out = begin
    if options[:reverse]
      # WO20: parse (the DSL cache makes re-parses free), reverse the
      # document, run the row's src through the reversed main stage —
      # the exact capture procedure, mirrored.
      doc = Interscript::DSL.parse(row["map"])
      Interscript::Interpreter.call(doc.reverse).call(row["src"])
    else
      Interscript.transliterate(row["map"], row["src"])
    end
  rescue StandardError, NotImplementedError => e
    # Forward keeps its self-comparison marker; the reverse gate maps
    # errors to `null`, the canonical marker the rs capture records.
    options[:reverse] ? "null" : "ERROR:#{e.class}:#{e.message.lines.first.to_s.strip[0, 160]}"
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
if options[:parity] || options[:reverse]
  puts "delta vs golden (cross-runtime): #{delta_vs_golden.size}"
  delta_vs_golden.first(10).each do |r|
    puts "  #{r[:map]} #{r[:src].inspect}: golden=#{r[:golden].inspect} ruby=#{r[:out].inspect}"
  end
end

failed = (delta_vs_baseline || []).any? ||
  ((options[:parity] || options[:reverse]) ? delta_vs_golden.any? : false)
exit(failed ? 1 : 0)
