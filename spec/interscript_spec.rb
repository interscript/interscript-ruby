# frozen_string_literal: true

RSpec.describe Interscript do
  mask = ENV["TRANSLIT_SYSTEM"] || "*"
  Dir["maps/#{mask}.yaml"].each do |system_file|
    context "#{system_file} system" do
      system = YAML.load_file(system_file)
      system_name = File.basename(system_file, ".yaml")

      system["tests"]&.reduce([]) do |testresults, test|
        it "test for #{test}" do
          result = Interscript.transliterate system_name, test["source"]
          expect(result.unicode_normalize).to eq(test["expected"].unicode_normalize)
        end
      end
    end
  end
end
