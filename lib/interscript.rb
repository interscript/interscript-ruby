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

      output = string.clone
      offsets = Array.new string.size, 1
      rules.each do |r|
        string.scan(/#{r["pattern"]}/) do |match|
          pos = Regexp.last_match.offset(0).first
          result = up_case_around?(string, pos) ? r["result"].upcase : r["result"]
          output[offsets[0..pos].sum - 1, match.size] = result
          offsets[pos] = r["result"].size - match.size + 1
        end
      end

      output.split('').map.with_index do |char, i|
        if (c = charmap[char])
          up_case_around?(output, i) ? c.upcase : c
        else
          char
        end
      end.join('')
    end

    private

    def up_case_around?(string, pos)
      return false if string[pos] != string[pos].upcase

      i = pos - 1
      i -= 1 while i.positive? && string[i] !~ /[[:alpha:]]/
      before = string[i].to_s.strip

      i = pos + 1
      i += 1 while i < string.size - 1 && string[i] !~ /[[:alpha:]]/
      after = string[i].to_s.strip

      !before.empty? && before == before.upcase || !after.empty? && after == after.upcase
    end
  end
end
