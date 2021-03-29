require "timeout"

cache = {}
mask = ENV["TRANSLIT_SYSTEM"] || "*"
maps = Interscript.maps(basename: false, select: mask)

# Precache can be used to compare interpreter to compiler performance
if ENV.include? "PRECACHE"
  each_compiler do |compiler|
    maps.each do |system_file|
      system_name = File.basename(system_file, ".imp")
      Interscript.transliterate(system_name, "", cache, compiler: compiler)
    end
  end
end

RSpec.describe Interscript do
  each_compiler do |compiler|
    describe compiler do
      maps.each do |system_file|
        system_name = File.basename(system_file, ".imp")
        context "#{system_name} system" do
          begin
            system = Interscript.parse(system_name)

            if system.tests && system.tests.data && system.tests.data.length > 0
              system.tests.data.each do |from,expected|
                testname = from[0...300].gsub("\n", " / ")
                it "test for #{testname}" do
                  Timeout::timeout(5) do
                    result = Interscript.transliterate(system_name, from, cache, compiler: compiler)
                    expect(result).to eq(expected)
                  end
                end
              end
            else
              it "can successfully run a dummy test" do
                result = Interscript.transliterate(system_name, "", cache, compiler: compiler)
                expect(result).to eq("")
              end
              if ENV["REQUIRE_TESTS"]
                it "has tests" do
                  expect(false).to eq(true)
                end
              end
            end
          rescue Interscript::MapNotFoundError => e
            it "loads" do
              raise e
            end
          end
        end
      end
    end
  end
end
