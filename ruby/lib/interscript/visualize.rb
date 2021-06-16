require 'erb'

class Interscript::Visualize
  @template = ERB.new(File.read(__dir__+"/visualize/map.html.erb"))

  def self.call(map_name)
    tplctx = self.new(Interscript.parse(map_name))
    @template.result(tplctx.get_binding)
  end

  def get_binding; binding; end

  def initialize(map)
    @map = map
  end

  attr_reader :map
end