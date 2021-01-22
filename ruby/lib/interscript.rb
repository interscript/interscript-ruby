require "interscript/version"
require "yaml"

module Interscript
  class MapNotFoundError < StandardError; end

  class << self
    def load_path
      @load_path ||= ['.', *Interscript.map_locations]
    end

    def locate map_name
      load_path.each do |i|
        # iml is an extension for a library, imp for a map
        ["iml", "imp"].each do |ext|
          f = File.expand_path("#{map_name}.#{ext}", i)
          return f if File.exist?(f)
        end
      end
      raise MapNotFoundError, "Couldn't locate #{map_name}"
    end

    def parse(map_name)
      Interscript::DSL.parse(map_name)
    end

    # Transliterates the string.
    def transliterate(system_code, string, maps={}, compiler: Interscript::Interpreter)
      # The current best implementation is Interpreter
      maps[[system_code, compiler.name]] ||= compiler.(system_code)
      maps[[system_code, compiler.name]].(string)
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

    def map_locations
      Gem.find_latest_files('interscript-maps.yaml').map do |i|
        YAML.load_file(i)["paths"].map do |j|
          File.expand_path(j, File.dirname(i))
        end
      end.flatten
    end

    # List all possible maps to use
    def maps(load_path: false, select: "*")
      if load_path
        paths = Interscript.load_path
      else
        paths = Interscript.map_locations
      end

      paths.map do |i|
        Dir["#{i}/#{select}.imp"]
      end.flatten
    end
  end
end

require 'interscript/stdlib'

require "interscript/compiler"
require "interscript/interpreter"

require 'interscript/dsl'
require 'interscript/node'
