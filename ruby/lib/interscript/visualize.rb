require 'erb'

class Interscript::Visualize
  def self.def_template(template)
    @template = ERB.new(File.read(__dir__+"/visualize/#{template}.html.erb"))
  end
  def get_binding; binding; end

  def self.call(*args)
    return Map.(*args) if self == Interscript::Visualize

    tplctx = self.new(*select_object(*args))
    @template.result(tplctx.get_binding)
  end

  def h(str)
    str.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
  end

  class Map < self
    def_template :map

    def self.select_object(map_name)
      Interscript.parse(map_name)
    end

    def initialize(map)
      @map = map
    end

    attr_reader :map

    def render_stage(map_name, stage)
      Stage.(map_name, stage)
    end
  end

  class Stage < self
    def_template :stage

    def self.select_object(map_name, stage_name)
      Interscript.parse(map_name).stages[stage_name]
    end
  
    def initialize(stage)
      @stage = stage
    end

    attr_reader :stage
  end  
end