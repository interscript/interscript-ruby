require "yaml"

module Interscript::DSL
  @cache = {}
  def self.parse(map_name, reverse: true)
    # map name aliases? here may be a place to wrap it

    return @cache[map_name] if @cache[map_name]

    # This is a composition, so let's make a new virtual map
    # that calls all maps in a sequence.
    if map_name.include? "|"
      map_parts = map_name.split("|").map(&:strip)

      doc = Interscript::DSL::Document.new(map_name) do
        map_parts.each_with_index do |i, idx|
          dependency i, as: :"part#{idx}"
        end

        stage {
          map_parts.each_with_index do |i, idx|
            run map[:"part#{idx}"].stage.main
          end
        }
      end.node

      return @cache[map_name] = doc
    end

    path = begin
      Interscript.locate(map_name)
    rescue Interscript::MapNotFoundError => e
      # But maybe we called the map in a reversed fashion?
      begin
        raise e if reverse == false # Protect from an infinite loop
        reverse_name = Interscript::Node::Document.reverse_name(map_name)
        return @cache[map_name] = parse(reverse_name, reverse: false).reverse
      rescue Interscript::MapNotFoundError
        raise e
      end
    end
    library = path.end_with?(".iml")

    map_name = File.basename(path, ".imp")
    map_name = File.basename(map_name, ".iml")

    ruby = []
    yaml = []

    file = File.read(path).split("\n")
    exc_fname = File.expand_path(path, Dir.pwd)

    md_reading = false
    md_indent = nil
    md_inner_indent = nil
    file.each do |l|
      if md_reading && l =~ /\A#{md_indent}\}\s*\z/
        md_reading = false
      elsif md_reading
        ruby << ""
        yaml << l
      elsif l =~ /\A(\s*)metadata\s*\{\z/
        md_indent = $1
        md_reading = true
      else
        yaml << ""
        ruby << l
      end
    end
    raise Interscript::MapLogicError, "metadata stage isn't terminated" if md_reading
    ruby, yaml = ruby.join("\n"), yaml.join("\n")

    obj = Interscript::DSL::Document.new(map_name)
    obj.instance_eval ruby, exc_fname, 1

    yaml = if yaml =~ /\A\s*\z/
      {}
    else
      unsafe_load = if YAML.respond_to? :unsafe_load
        :unsafe_load
      else
        :load
      end
      YAML.public_send(unsafe_load, yaml, filename: exc_fname)
    end

    md = Interscript::DSL::Metadata.new(yaml: true, map_name: map_name, library: library) do
      yaml.each do |k,v|
        public_send(k.to_sym, v)
      end
    end
    obj.node.metadata = md.node

    @cache[map_name] = obj.node
  end
end

require 'interscript/dsl/symbol_mm'
require 'interscript/dsl/items'

require 'interscript/dsl/document'
require 'interscript/dsl/group'
require 'interscript/dsl/stage'
require 'interscript/dsl/metadata'
require 'interscript/dsl/tests'
require 'interscript/dsl/aliases'
