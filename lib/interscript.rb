# frozen_string_literal: true

require 'yaml'

# Transliteration
module Interscript
  SYSTEM_DEFINITIONS_PATH = File.expand_path('../maps', __dir__)

  class << self
    def transliterate_file(system_code, input_file, output_file)
      input = File.read(input_file)
      output = transliterate(system_code, input)

      File.open(output_file, "w") do |f|
        f.puts(output)
      end
      puts "Output written to: #{output_file}"
    end

    def load_system_definition(system_code)
      YAML.load_file(File.join(SYSTEM_DEFINITIONS_PATH, "#{system_code}.yaml"))
    end

    def transliterate(system_code, string)
      system = load_system_definition(system_code)

      rules = system["map"]["rules"] || []
      charmap = system["map"]["characters"] || {}

      rules.each do |r|
        string.gsub! %r{#{r["pattern"]}}, r["result"]
      end

      string.split('').map do |char|
        charmap[char] || char
      end.join('')
    end
  end
end
