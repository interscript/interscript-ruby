require 'pathname'

module Interscript
  module Fs
    def sub_replace(string, pos, size, repl)
      string[pos..pos + size - 1] = repl
      string
    end

    def root_path
      @root_path ||= Pathname.new(File.join(File.dirname(__dir__), ".."))
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

    def import_python_modules
      begin
        pyimport :g2pwrapper
      rescue
        pyimport :sys
        sys.path.append(root_path.to_s + "/lib/")
        pyimport :g2pwrapper
      end
    end

    def external_process(process_name, string)
      import_python_modules

      case process_name
      when 'sequitur.pythainlp_lexicon'
        return g2pwrapper.transliterate('pythainlp_lexicon', string)
      when 'sequitur.wiktionary_phonemic'
        return g2pwrapper.transliterate('wiktionary_phonemic', string)
      else
        raise ExternalProcessNotRecognizedError.new
      end

    rescue
      raise ExternalProcessUnavailableError.new
    end

    def external_processing(mapping, string)
      # Segmentation
      string = external_process(mapping.segmentation, string) if mapping.segmentation

      # Transliteration/Transcription
      string = external_process(mapping.transcription, string) if mapping.transcription

      string
    end

    def aliases (refresh: false)
      file = root_path.join("./aliases.json").to_s
      if !refresh && File.exist?(file)
        JSON.load(File.read(file))
      elsif !refresh && @aliases
        @aliases
      else
        @aliases = {}
        Dir[root_path.join('./maps/*.yaml').to_s].each do |yaml_file|
          org_name = File.basename(yaml_file, ".yaml")
          map = YAML.load_file(yaml_file)
          (map["alias"] || {}).each do |k,v|
            @aliases[v["code"]] = org_name
          end
        end

        # Try to save it to a file, but not force it.
        File.write("aliases.json", JSON.dump(@aliases)) rescue nil

        @aliases
      end
    end

    private

    def map_exist?(map)
      File.exist?(root_path.join("./maps/" + map + ".yaml").to_s)
    end

    def mkregexp(regexpstring)
      /#{regexpstring}/u
    end

  end
end
