require 'thor'
require 'interscript'
require 'json'

module Interscript
  # Command line interface
  class Command < Thor
    desc '<file>', 'Transliterate text'
    option :system, aliases: '-s', required: true, desc: 'Transliteration system'
    option :output, aliases: '-o', required: false, desc: 'Output file'
    option :compiler, aliases: '-c', required: false, desc: 'Compiler (eg. Interscript::Compiler::Python)'
    # Was this option really well thought out? The last parameter is a cache, isn't it?
    #option :map, aliases: '-m', required: false, default: "{}", desc: 'Transliteration mapping json'

    def translit(input)
      compiler = if options[:compiler]
                   compiler = options[:compiler].split("::").last.downcase
                   require "interscript/compiler/#{compiler}"
                   Object.const_get(options[:compiler])
                 else
                   Interscript::Interpreter
                 end

      if options[:output]
        Interscript.transliterate_file(options[:system], input, options[:output], compiler: compiler)
      else
        puts Interscript.transliterate(options[:system], IO.read(input), compiler: compiler)
      end
    end

    desc 'list', 'Prints allowed transliteration systems'
    def list
      Interscript.maps(load_path: true).each do |path|
        puts path
      end
    end

    desc 'stats', 'Prints statistics about the maps we have'
    def stats
      maps = Interscript.maps(load_path: true)
      parsed_maps = maps.map { |i| [i, Interscript.parse(i)] }.to_h
      maps_by_rule_count = parsed_maps.transform_values do |map|
        map.stages.values.map { |i| i.children.map { |j| j.is_a?(Interscript::Node::Group) ? j.children : j } }.flatten.count
      end

      authorities, languages, source_scripts, target_scripts = 4.times.map do |i|
        maps.group_by { |map| map.split('-')[i] }
      end

      puts <<~END
        Languages supported: #{languages.keys.count}
        Source scripts supported: #{source_scripts.keys.count}
        Target scripts supported: #{target_scripts.keys.count}
        Authorities supported: #{authorities.keys.count}
        Total number of rules in Interscript: #{maps_by_rule_count.values.sum}

      END

      authorities.each do |auth, auth_maps|
        rule_counts = auth_maps.map { |i| maps_by_rule_count[i] }
        puts <<~END
          Authority #{auth}:
          * Conversion systems: #{auth_maps.count}
          * Total number of rules: #{rule_counts.sum}

        END
      end

      puts <<~END
        Interesting facts:
        * #{maps_by_rule_count.max_by { |i| i.last }.first} has the most rules
        * Authority #{authorities.max_by { |i| i.last.count }.first} has the most systems
        * Language #{languages.max_by { |i| i.last.count }.first} has the most systems
        * Source script #{source_scripts.max_by { |i| i.last.count }.first} has the most systems
        * Target script #{target_scripts.max_by { |i| i.last.count }.first} has the most systems
      END
    end
  end
end
