require "erb"

class Interscript::Visualize
  autoload :Nodes, "interscript/visualize/nodes"
  autoload :JSON, "interscript/visualize/json"

  def self.def_template(template)
    @template = ERB.new(File.read(__dir__ + "/visualize/#{template}.html.erb"))
  end

  def get_binding
    binding
  end

  def self.call(*args)
    return Map.call(*args) if self == Interscript::Visualize

    tplctx = new(*args)
    @template.result(tplctx.get_binding)
  end

  class Map < self
    def_template :map

    def initialize(map_name)
      @map = Interscript.parse(map_name)
    end

    attr_reader :map

    def render_stage(map_name, stage)
      Stage.call(map_name, stage)
    end
  end

  class Group < self
    def_template :group

    def initialize(map, group, style = nil)
      @map = map
      @group = group
      @style = style
    end

    attr_reader :map, :group

    def render_group(map, group, style = nil)
      Group.call(map, group, style)
    end
  end

  class Stage < Group
    def_template :group

    def initialize(map_name, stage_name, style = nil)
      @map = Interscript.parse(map_name)
      @group = map.stages[stage_name]
      @style = style
    end
  end
end
