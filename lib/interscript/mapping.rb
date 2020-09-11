require 'rambling-trie'
require 'yaml' unless RUBY_ENGINE == 'opal'
require 'json'

module Interscript

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
      :chain,
      :character_separator,
      :word_separator,
      :title_case,
      :downcase,
      :dictionary,
      :characters_hash,
      :dictionary_hash,
      :segmentation,
      :transcription,
      :dictionary_trie
    )

    def initialize(system_code, options = {})
      @system_code = system_code
      @depth = options.fetch(:depth, 0).to_i

      unless RUBY_ENGINE == 'opal'
        @system_path = options.fetch(:system_code, default_path)
      end

      load_and_serialize_system_mappings
    end

    def self.for(system_code, options = {})
      new(system_code, options)
    end

    def load_and_serialize_system_mappings
      return if depth >= 5

      mappings = load_system_mappings
      serialize_system_mappings(mappings)
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
      if RUBY_ENGINE == 'opal'
        load_opal_mappings
      else
        load_fs_mappings
      end
    end

    def load_opal_mappings
      JSON.parse(`InterscriptMaps[#{system_code}]`)
    end

    def load_fs_mappings
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
      @chain = mappings.fetch("chain", [])
      @character_separator = mappings["map"]["character_separator"] || nil
      @word_separator = mappings["map"]["word_separator"] || nil
      @title_case = mappings["map"]["title_case"] || false
      @downcase = mappings["map"]["downcase"] || false
      @rules = mappings["map"]["rules"] || []
      @postrules = mappings["map"]["postrules"] || []
      @characters = mappings["map"]["characters"] || {}
      @dictionary = mappings["map"]["dictionary"] || {}
      @segmentation = mappings["map"]["segementation"] || nil
      @transcription = mappings["map"]["transcription"] || nil

      include_inherited_mappings(mappings)
      build_hashes
      build_trie
    end

    def include_inherited_mappings(mappings)
      inherit_systems = [].push(mappings["map"]["inherit"]).flatten

      inherit_systems.each do |inherit_system|
        next unless inherit_system

        inherited_mapping = Mapping.for(inherit_system, depth: depth + 1)

        @rules = [inherited_mapping.rules, rules].flatten
        @postrules = [inherited_mapping.postrules, postrules].flatten
        @characters = (inherited_mapping.characters|| {}).merge(characters)
        @dictionary = (inherited_mapping.dictionary|| {}).merge(dictionary)
      end
    end

    def build_hashes
      @characters_hash = characters&.sort_by { |k, _v| k.size }&.reverse&.to_h
      @dictionary_hash = dictionary&.sort_by { |k, _v| k.size }&.reverse&.to_h
    end

    def build_trie
      @dictionary_trie = Rambling::Trie.create
      dictionary_trie.concat dictionary.keys
    end
  end
end
