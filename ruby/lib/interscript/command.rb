require 'thor'
require 'interscript'
require 'json'
module Interscript
  # Command line interface
  class Command < Thor
    desc '<file>', 'Transliterate text'
    option :system, aliases: '-s', required: true, desc: 'Transliteration system'
    option :output, aliases: '-o', required: false, desc: 'Output file'
    # Was this option really well thought out? The last parameter is a cache, isn't it?
    #option :map, aliases: '-m', required: false, default: "{}", desc: 'Transliteration mapping json'

    def translit(input)
      if options[:output]
        Interscript.transliterate_file(options[:system], input, options[:output]) #, JSON.parse(options[:map]))
      else
        puts Interscript.transliterate(options[:system], IO.read(input))
      end
    end

    desc 'list', 'Prints allowed transliteration systems'
    def list
      dir = File.expand_path '../../../maps/*.yaml', __dir__
      Dir[dir].each do |path|
        puts File.basename path, '.yaml'
      end
    end
  end
end
