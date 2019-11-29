require 'thor'
require 'interscript'

module Interscript
  # Command line interface
  class Command < Thor
    desc '<file>', 'Transliterate text'
    option :system, aliases: '-s', required: true, desc: 'Transliteration system'
    option :output, aliases: '-o', required: false, desc: 'Output file'

    def translit(input)
      if options[:output]
        Interscript.transliterate_file(options[:system], input, options[:output])
      else
        puts Interscript.transliterate(options[:system], IO.read(input))
      end
    end

    desc 'list', 'Prints allowed transliteration systems'
    def list
      dir = File.expand_path '../../maps/*.yaml', __dir__
      Dir[dir].each do |path|
        puts File.basename path, '.yaml'
      end
    end
  end
end
