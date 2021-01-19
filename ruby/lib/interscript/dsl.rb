require "yaml"

module Interscript::DSL
  @cache = {}
  def self.parse(map_name)
    # map name aliases? here may be a place to wrap it

    return @cache[map_name] if @cache[map_name]
    path = Interscript.locate(map_name)

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
    raise ArgumentError, "metadata stage isn't terminated" if md_reading
    ruby, yaml = ruby.join("\n"), yaml.join("\n")

    obj = Interscript::DSL::Document.new
    obj.instance_eval ruby, exc_fname, 1

    yaml = if yaml =~ /\A\s*\z/
      {}
    else
      YAML.load(yaml, exc_fname)
    end

    md = Interscript::DSL::Metadata.new(yaml: true) do
      yaml.each do |k,v|
        public_send(k.to_sym, v)
      end
    end
    obj.node.metadata = md.node
    obj.node.name = map_name

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
