# frozen_string_literal: true

require "interscript"
require "tmpdir"
require "fileutils"
require "yaml"

RSpec.describe Interscript do
  describe ".locate_map_gems_yaml" do
    it "finds the registry yaml via Gem.find_latest_files when available" do
      Dir.mktmpdir do |dir|
        gem_dir = File.join(dir, "gems", "interscript-maps-9.9.9")
        FileUtils.mkdir_p(gem_dir)
        yaml_path = File.join(gem_dir, "interscript-maps.yaml")
        File.write(yaml_path, { "paths" => ["maps"] }.to_yaml)
        spec = Struct.new(:name, :full_gem_path).new("interscript-maps", gem_dir)
        allow(Gem::Specification).to receive(:latest_specs).and_return([spec])
        allow(Gem).to receive(:find_latest_files).with("interscript-maps.yaml").and_return([yaml_path])
        expect(Interscript.locate_map_gems_yaml).to include(yaml_path)
      end
    end

    it "falls back to a direct gem-dir glob when Gem.find_latest_files is unavailable (rubygems 4)" do
      Dir.mktmpdir do |dir|
        gem_dir = File.join(dir, "gems", "interscript-maps-9.9.9")
        FileUtils.mkdir_p(File.join(gem_dir, "maps"))
        yaml_path = File.join(gem_dir, "interscript-maps.yaml")
        File.write(yaml_path, { "paths" => ["maps"] }.to_yaml)
        spec = Struct.new(:name, :full_gem_path).new("interscript-maps", gem_dir)
        allow(Gem::Specification).to receive(:latest_specs).and_return([spec])
        allow(Gem).to receive(:find_latest_files).with("interscript-maps.yaml")
          .and_raise(RuntimeError, "undefined method 'files' for Gem::StubSpecification")
        expect(Interscript.locate_map_gems_yaml).to include(yaml_path)
      end
    end
  end
end
