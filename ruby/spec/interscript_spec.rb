require "timeout"
require "interscript/compiler/ruby"

RSpec.describe Interscript do
  [Interscript::Interpreter, Interscript::Compiler::Ruby].each do |compiler|
    context compiler do
      mask = ENV["TRANSLIT_SYSTEM"] || "*"
      maps = Interscript.maps(select: mask)

      maps.each do |system_file|
        system_name = File.basename(system_file, ".imp")
        context "#{system_name} system" do
          begin
            system = Interscript.parse(system_name)

            cache = {}

            if system.tests && system.tests.data
              system.tests.data.each do |from,expected|
                it "test for #{from}" do
                  Timeout::timeout(5) do
                    result = Interscript.transliterate(system_name, from, cache, compiler: compiler)
                    expect(result).to eq(expected)
                  end
                end
              end
            else
              it "has tests" do
                expect(false).to be(true)
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
