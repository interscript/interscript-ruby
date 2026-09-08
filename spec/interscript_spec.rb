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
    next if ENV["ONLY_COMPILER"] && compiler.name != ENV["ONLY_COMPILER"]

    describe compiler do
      compiler_maps = Interscript.exclude_maps(maps, compiler: compiler)

      compiler_maps.each do |system_file|
        system_name = File.basename(system_file, ".imp")
        my_system_name = if ENV["REVERSE"]
          Interscript::Node::Document.reverse_name(system_name)
        else
          system_name
        end

        context "#{my_system_name} system" do
          system = Interscript.parse(system_name)
          system = system.reverse if ENV["REVERSE"]

          if system.tests&.data && system.tests.data.length > 0
            system.tests.data.each do |from, expected, reverse_run|
              next if reverse_run == true

              testname = from[0...300].gsub("\n", " / ")
              it "test for #{testname}" do
                # Allow a bigger timeout for Rababa so that model files
                # can be provisioned. This is temporary until we find a
                # better location for this code.
                timeout = /rababa/.match?(my_system_name) ? 100 : 5
                Timeout.timeout(timeout) do
                  result = Interscript.transliterate(my_system_name, from, cache, compiler: compiler)
                  expect(result).to eq(expected)
                end
              end
            end
          else
            it "can successfully run a dummy test" do
              result = Interscript.transliterate(my_system_name, "", cache, compiler: compiler)
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
