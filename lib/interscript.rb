require "interscript/version"
require "yaml"

module Interscript
  # An error caused by a lack of some map
  class MapNotFoundError < StandardError; end
  # An error caused by a missing dependency
  class ExternalUtilError < StandardError; end
  # An error caused by a particular compiler
  class SystemConversionError < StandardError; end
  # An error caused by an incorrect map implementation
  class MapLogicError < StandardError; end

  class << self
    def load_path
      @load_path ||= ['.', *Interscript.map_locations]
    end

    def locate map_name
      map_name = map_aliases[map_name] if map_aliases.include? map_name

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

    def load(system_code, maps={}, compiler: Interscript::Interpreter)
      maps[[system_code, compiler.name]] ||= compiler.(system_code)
    end

    # Transliterates the string.
    def transliterate(system_code, string, maps={}, compiler: Interscript::Interpreter)
      # The current best implementation is Interpreter
      load(system_code, maps, compiler: compiler).(string)
    end

    # Gives each possible value of the transliteration.
    def transliterate_each(system_code, string, maps={}, &block)
      load(system_code, maps).(string, each: true, &block)
    end

    def transliterate_file(system_code, input_file, output_file, maps={}, compiler: Interscript::Interpreter)
      input = File.read(input_file)
      output = transliterate(system_code, input, maps, compiler: compiler)

      File.open(output_file, 'w') do |f|
        f.puts(output)
      end

      puts "Output written to: #{output_file}"
      output_file
    end

    # Detects the transliteration that gives the most close approximation
    # of transliterating source into destination.
    #
    # Set multiple: true to get a full report.
    def detect(source, destination, **kwargs)
      detector = Detector.new
      detector.set_from_kwargs(**kwargs)
      detector.(source, destination)
    end

    def map_gems
      @map_gems ||= Gem.find_latest_files('interscript-maps.yaml').map do |i|
        [i, YAML.load_file(i)]
      end.to_h
    end

    def map_locations
      @map_locations ||= map_gems.map do |i,v|
        paths = v["paths"].dup
        paths += v["staging"] if ENV["INTERSCRIPT_STAGING"] && v["staging"]

        paths.map do |j|
          File.expand_path(j, File.dirname(i))
        end
      end.flatten
    end

    def secryst_index_locations
      @secryst_index_locations ||= map_gems.map do |i,v|
        v["secryst-models"]
      end.compact.flatten
    end

    def rababa_configs
      @rababa_configs ||= map_gems.map do |i,v|
        v["rababa-configs"]
      end.compact.inject({}) do |a,b|
        a.merge(b)
      end
    end

    # This code is borrowed from Secryst and should end up in Rababa, but for now,
    # let's keep it here.
    def rababa_provision(model_name, model_uri)
      require 'fileutils'
      require 'open-uri'

      # We provision the environment in the following way:
      # First, we try the RABABA_DATA environment variable. If that's available,
      # we use it to store the Rababa data we need. Otherwise, we try the following
      # paths:

      possible_paths = [
        "/var/lib/rababa",
        "/usr/local/share/rababa",
        "/usr/share/rababa",
        File.join(Dir.home, ".local/share/rababa")
      ]

      # We find the first writable path

      write_path = nil

      ([ENV["RABABA_DATA"]] + possible_paths).compact.each do |path|
        FileUtils.mkdir_p(path)
        write_path = path
        break
      rescue
      end
  
      raise ExternalUtilError, "Can't find a writable path for Rababa. Consider setting a RABABA_DATA environment variable" unless write_path

      model_path = "#{write_path}/model-#{model_name}.onnx"

      # Redownload every hour
      if File.exist?(model_path) && File.mtime(model_path) + 3600 >= Time.now
        return model_path
      else
        data = URI.open(model_uri, encoding: "BINARY").read
        File.binwrite(model_path, data)
        return model_path
      end
    end

    def map_aliases
      return @map_aliases if @map_aliases

      @map_aliases = {}
      map_gems.each do |i,v|
        (v["aliases"] || {}).each do |code, value|
          value.each do |al, map|
            @map_aliases[al] = map["alias_to"]
          end
        end
      end
      @map_aliases
    end

    # List all possible maps to use
    def maps(basename: true, load_path: false, select: "*", libraries: false)
      paths = load_path ? Interscript.load_path : Interscript.map_locations
      ext = libraries ? "iml" : "imp"

      imps = paths.map { |i| Dir["#{i}/#{select}.#{ext}"] }.flatten

      basename ? imps.map { |j| File.basename(j, ".#{ext}") } : imps
    end

    # Removes the excluded maps for a given compiler and RUBY_PLATFORM.
    # To be used by tests
    # and builders. It uses the `skip` directive in interscript-maps.yaml
    def exclude_maps(maps, compiler:, platform: true)
      map_gems.each do |i,v|
        [compiler.name, (Gem::Platform.local.os if platform)].compact.each do |name|
          skips = v.dig('skip', name) || []
          skips.each do |skip|
            skip_re = /#{Regexp.escape(skip).gsub("\\*", ".*?")}/
            maps = maps.grep_v(skip_re)
          end
        end
      end
      maps
    end
  end
end

require 'interscript/stdlib'

require "interscript/compiler"
require "interscript/interpreter"

require 'interscript/dsl'
require 'interscript/node'

require 'interscript/detector'
