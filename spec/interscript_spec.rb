# frozen_string_literal: true

require "diffy"

RSpec.describe Interscript do
  Dir["maps/*.yaml"].each do |system_file|
    context "#{system_file} system" do
      system = YAML.load_file(system_file)
      system_name = File.basename(system_file, ".yaml")

      tests = system["tests"]&.reduce([]) do |testresults, test|

        it "test for #{test}" do
          result = Interscript.transliterate system_name, test["source"]
          # puts "#{test["expected"]} result #{result}"
          expect(result).to eq(test["expected"])

          # diff = Diffy::Diff.new test["expected"], result
          # puts diff.inspect
          # expect diff.to_s.empty?
        end

      end

    end
  end

end
