require 'yaml'
require 'singleton'

class Interscript
  include Singleton
  
  SYSTEM_DEFINITIONS_PATH = File.expand_path('../../maps', __FILE__)

  def initialize
    @systems = {}
  end

  def transliterate_file(system_code, input_file, output_file)
    input = File.read(input_file)
    output = transliterate(system_code, input)

    File.open(output_file, "w") do |f|
      f.puts(output)
    end
    puts "Output written to: #{output_file}"
  end

  def load_system_definition(system_code)
    @systems[system_code] ||= YAML.load_file(File.join(SYSTEM_DEFINITIONS_PATH, "#{system_code}.yaml"))
  end

  def get_system(system_code)
    @systems[system_code]
  end

  def system_char_map(system_code)
    get_system(system_code)["map"]["characters"]
  end

  def system_rules(system_code)
    get_system(system_code)["map"]["rules"]
  end

  def transliterate(system_code, string)
    load_system_definition(system_code)

    # TODO: also need to support regular expressions via system_rules(system_code), before system_char_map

    character_map = system_char_map(system_code)

    string.split('').map do |char|
      converted_char = character_map[char] ? character_map[char] : char
      string[char] = converted_char
    end.join('')
  end

end

