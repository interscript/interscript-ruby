module Interscript::DSL
  class MapNotFoundError < StandardError; end

  @load_path = ['.', File.expand_path("../../../maps", __dir__)]
  def self.load_path; @load_path; end
  def self.load_path= x; @load_path = x; end

  def self.locate map_name
    @load_path.each do |i|
      # iml is an extension for a library, imp for a map
      ["iml", "imp"].each do |ext|
        f = File.expand_path("#{map_name}.#{ext}", i)
        return f if File.exist?(f)
      end
    end
    raise MapNotFoundError, "Couldn't locate #{map_name}"
  end

  @cache = {}
  def self.parse(map_name)
    # map name aliases? here may be a place to wrap it

    return @cache[map_name] if @cache[map_name]
    path = locate(map_name)

    obj = Interscript::DSL::Document.new
    obj.instance_eval File.read(path), File.expand_path(path, Dir.pwd), 1
    @cache[map_name] = obj.node
  end

end

require 'interscript/dsl/items'

require 'interscript/dsl/document'
require 'interscript/dsl/group'
require 'interscript/dsl/stage'
require 'interscript/dsl/metadata'
require 'interscript/dsl/tests'
require 'interscript/dsl/aliases'
