module Interscript
  class InvalidSystemError < StandardError; end

  class Mapping
    attr_reader(
      :id,
      :url,
      :name,
      :notes,
      :rules,
      :tests,
      :language,
      :postrules,
      :characters,
      :description,
      :authority_id,
      :creation_date,
      :source_script,
      :destination_script,
      :character_separator,
      :word_separator,
      :title_case,
      :downcase
    )

    def initialize(system_code, options = {})
      @system_code = system_code
      @depth = options.fetch(:depth, 0).to_i
      @system_path = options.fetch(:system_code, default_path)

      load_and_serialize_system_mappings
    end

    def self.for(system_code, options = {})
      new(system_code, options)
    end

    def load_and_serialize_system_mappings
      if depth < 3
        mappings = load_system_mappings
        serialize_system_mappings(mappings)
      end
    end

    private

    attr_reader :depth, :system_code, :system_path

    def system_code_file
      [system_code, "yaml"].join(".")
    end

    def default_path
      @default_path ||= Interscript.root_path.join("maps")
    end

    def load_system_mappings
      YAML.load_file(system_path.join(system_code_file))
    rescue Errno::ENOENT
      raise Interscript::InvalidSystemError.new("No system mappings found")
    end

    def serialize_system_mappings(mappings)
      @id = mappings.fetch("id", nil)
      @url = mappings.fetch("url", nil)
      @name = mappings.fetch("name", nil)
      @notes = mappings.fetch("notes", nil)
      @tests = mappings.fetch("tests", [])
      @language = mappings.fetch("language", nil)
      @description = mappings.fetch("description", nil)
      @authority_id = mappings.fetch("authority_id", nil)
      @creation_date = mappings.fetch("creation_date", nil)
      @source_script = mappings.fetch("source_script", nil)
      @destination_script = mappings.fetch("destination_script", nil)
      @character_separator = mappings["map"]["character_separator"] || nil
      @word_separator = mappings["map"]["word_separator"] || nil
      @title_case = mappings["map"]["title_case"] || false
      @downcase = mappings["map"]["downcase"] || false
      @rules = mappings["map"]["rules"] || []
      @postrules = mappings["map"]["postrules"] || []
      @characters = mappings["map"]["characters"] || {}

      include_inherited_mappings(mappings)
    end

    def include_inherited_mappings(mappings)
      inherit_systems = mappings["map"]["inherit"]

      if inherit_systems
        inherited_mapping = Mapping.for(inherit_systems, depth: depth + 1)

        @rules = [inherited_mapping.rules, rules].flatten
        @postrules = [inherited_mapping.postrules, postrules].flatten
        @characters = inherited_mapping.characters.merge(characters)
      end
    end
  end
end
