require "timeout"

RSpec.describe Interscript do
  mask = ENV["TRANSLIT_SYSTEM"] || "*"
  maps = Dir["../maps/#{mask}.imp"]

  maps.each do |system_file|
    system_name = File.basename(system_file, ".imp")
    context "#{system_name} system" do
      begin
        system = Interscript::DSL.parse(system_name)

        cache = {}

        system.tests.data.each do |from,expected|
          it "test for #{from}" do
            Timeout::timeout(5) do
              result = Interscript.transliterate(system_name, from, cache)
              expect(result).to eq(expected)
            end
          end
        end
      rescue Interscript::DSL::MapNotFoundError => e
        it "loads" do
          raise e
        end
      end
    end
  end
end
