require "interscript/version"

module Interscript
  class << self
    # Transliterates the string.
    def transliterate(system_code, string, maps={})
      # The current best implementation is Interpreter
      impl = Interscript::Interpreter

      maps[system_code] ||= impl.(system_code)
      maps[system_code].(string)
    end

    def transliterate_file(system_code, input_file, output_file, maps={})
      input = File.read(input_file)
      output = transliterate(system_code, input, maps)

      File.open(output_file, 'w') do |f|
        f.puts(output)
      end

      puts "Output written to: #{output_file}"
      output_file
    end
  end
end

require 'interscript/stdlib'

require "interscript/compiler"
require "interscript/interpreter"

require 'interscript/dsl'
require 'interscript/node'
