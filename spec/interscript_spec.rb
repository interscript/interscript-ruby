# frozen_string_literal: true

require "timeout"
require "pycall/import"
include PyCall::Import

# Cache the map aliases early so they don't timeout the tests
Interscript.aliases

RSpec.describe Interscript do
  mask = ENV["TRANSLIT_SYSTEM"] || "*"
  maps = Dir["maps/#{mask}.yaml"]

  fail "TRANSLIT_SYSTEM env didn't match any map configuration" if maps.empty?

  maps.each do |system_file|
    context "#{system_file} system" do
      system = YAML.load_file(system_file)
      system_name = File.basename(system_file, ".yaml")

      cache = {}
      # Let's preload the cache but silence the exception if not possible
      # (it will be reraised during the test)
      Interscript.transliterate(system_name, "", cache) rescue nil

      system["tests"]&.uniq&.reduce([]) do |_, test|
        it "test for #{test}" do
          Timeout::timeout(5) do
            result = Interscript.transliterate(system_name, test["source"], cache, { :language => test["language"] })
            expected = test["expected"]&.unicode_normalize
            expect(result).to eq(expected)
          end
        end
      end
    end
  end
end
