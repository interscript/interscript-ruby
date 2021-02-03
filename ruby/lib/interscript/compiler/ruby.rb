$main_binding = binding

class Interscript::Compiler::Ruby < Interscript::Compiler
  def compile(map)
    @map = map
    @parallel_trees = {}
    c = "require 'interscript/stdlib'\n"
    c << "if !defined?(Interscript::Maps); module Interscript; module Maps\n"
    c << "module Cache; end\n"
    c << "class Map < Struct.new(:stages, :aliases, :aliases_re); end\n"
    c << "@maps = Hash.new { |h,id| h[id] = Map.new({},{},{}) }\n"
    c << "def self.has_map?(map);                      @maps.include?(map); end\n"
    c << "def self.add_map_alias(map,name,value)       @maps[map].aliases[name] = value; end\n"
    c << "def self.add_map_alias_re(map,name,value)    @maps[map].aliases_re[name] = value; end\n"
    c << "def self.add_map_stage(map,stage,&block);    @maps[map].stages[stage] = block; end\n"
    c << "def self.get_alias(map,name);                @maps[map].aliases[name]; end\n"
    c << "def self.get_alias_re(map,name);             @maps[map].aliases_re[name]; end\n"
    c << "def self.transcribe(map,string,stage=:main); @maps[map].stages[stage].(string); end\n"
    c << "end; end; end\n"
    c

    map.aliases.each do |name, value|
      val = compile_item(value.data, map, :str)
      c << "Interscript::Maps.add_map_alias(#{map.name.inspect}, #{name.inspect}, #{val})\n"
      val = '/'+compile_item(value.data, map, :re).gsub('/', '\\\\/')+'/'
      c << "Interscript::Maps.add_map_alias_re(#{map.name.inspect}, #{name.inspect}, #{val})\n"
    end

    map.stages.each do |_, stage|
      c << compile_rule(stage, @map, true)
    end
    @parallel_trees.each do |k,v|
      c << "Interscript::Maps::Cache::PTREE_#{k} ||= #{v.inspect}\n"
    end
    @code = c
  end

  def compile_rule(r, map = @map, wrapper = false)
    c = ""
    case r
    when Interscript::Node::Stage
      c += "Interscript::Maps.add_map_stage \"#{@map.name}\", #{r.name.inspect} do |s|\n"
      c += "s = s.dup\n"
      r.children.each do |t|
        c += compile_rule(t, map)
      end
      c += "s\n"
      c += "end\n"
    when Interscript::Node::Group::Parallel
      a = []
      r.children.each do |i|
        raise ArgumentError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i
        raise ArgumentError, "Can't parallelize rules with :before" if i.before
        raise ArgumentError, "Can't parallelize rules with :after" if i.after
        raise ArgumentError, "Can't parallelize rules with :not_before" if i.not_before
        raise ArgumentError, "Can't parallelize rules with :not_after" if i.not_after

        a << [compile_item(i.from, map, :par), compile_item(i.to, map, :parstr)]
      end
      ah = a.hash.abs
      unless @parallel_trees.include? ah
        tree = Interscript::Stdlib.parallel_replace_compile_tree(a)
        @parallel_trees[ah] = tree
      end
      c += "s = Interscript::Stdlib.parallel_replace_tree(s, Interscript::Maps::Cache::PTREE_#{ah})\n"
    when Interscript::Node::Rule::Sub
      from = "/#{build_regexp(r, map).gsub("/", "\\\\/")}/"
      to = compile_item(r.to, map, :str)
      c += "s.gsub!(#{from}, #{to})\n"
    when Interscript::Node::Rule::Funcall
      c += "s = Interscript::Stdlib::Functions.#{r.name}(s, #{r.kwargs.inspect[1..-2]})\n"
    when Interscript::Node::Rule::Run
      if r.stage.map
        doc = map.dep_aliases[r.stage.map].document
        stage = doc.imported_stages[r.stage.name]
      else
        stage = map.imported_stages[r.stage.name]
      end
      c += "s = Interscript::Maps.transcribe(#{stage.doc_name.inspect}, s, #{stage.name.inspect})\n"
    else
      raise ArgumentError, "Can't compile unhandled #{r.class}"
    end
    c
  end

  def build_regexp(r, map=@map)
    from = compile_item(r.from, map, :re)
    before = compile_item(r.before, map, :re) if r.before
    after = compile_item(r.after, map, :re) if r.after
    not_before = compile_item(r.not_before, map, :re) if r.not_before
    not_after = compile_item(r.not_after, map, :re) if r.not_after

    re = ""
    re += "(?<=#{before})" if before
    re += "(?<!#{not_before})" if not_before
    re += from
    re += "(?!#{not_after})" if not_after
    re += "(?=#{after})" if after
    re
  end

  def compile_item i, doc=@map, target=nil
    i = i.first_string if %i[str parstr].include? target
    i = Interscript::Node::Item.try_convert(i)
    target = :par if target == :parstr

    out = case i
    when Interscript::Node::Item::Alias
      astr = if i.map
        d = doc.dep_aliases[i.map].document
        a = d.imported_aliases[i.name]
        raise ArgumentError, "Alias #{i.name} of #{i.stage.map} not found" unless a
        "Interscript::Maps.get_alias_ALIASTYPE(#{a.doc_name.inspect}, #{a.name.inspect})"
      elsif Interscript::Stdlib::ALIASES.include?(i.name)
        if target != :re && Interscript::Stdlib.re_only_alias?(i.name)
          raise ArgumentError, "Can't use #{i.name} in a #{target} context"
        end

        "Interscript::Stdlib::ALIASES[#{i.name.inspect}]"
      else
        a = doc.imported_aliases[i.name]
        raise ArgumentError, "Alias #{i.name} not found" unless a

        "Interscript::Maps.get_alias_ALIASTYPE(#{a.doc_name.inspect}, #{a.name.inspect})"
      end

      if target == :str
        astr = astr.sub("_ALIASTYPE(", "(")
      elsif target == :re
        astr = "\#{#{astr.sub("_ALIASTYPE(", "_re(")}}"
      elsif target == :par
        raise NotImplementedError, "Can't use aliases in parallel mode yet"
      end
    when Interscript::Node::Item::String
      if target == :str
        # Replace \1 with \\1, this is weird, but it works!
        i.data.gsub("\\", "\\\\\\\\").inspect
      elsif target == :par
        i.data
      elsif target == :re
        Regexp.escape(i.data)
      end
    when Interscript::Node::Item::Group
      if target == :par
        raise NotImplementedError, "Can't concatenate in parallel mode yet"
      elsif target == :str
        i.children.map { |j| compile_item(j, doc, target) }.join("+")
      elsif target == :re
        i.children.map { |j| compile_item(j, doc, target) }.join
      end
    when Interscript::Node::Item::CaptureGroup
      if target != :re
        raise ArgumentError, "Can't use a CaptureGroup in a #{target} context"
      end
      "(" + compile_item(i.data, doc, target) + ")"
    when Interscript::Node::Item::CaptureRef
      if target == :par
        raise ArgumentError, "Can't use CaptureRef in parallel mode"
      elsif target == :re
        "\\#{i.id}"
      elsif target == :str
        "\"\\\\#{i.id}\""
      end
    when Interscript::Node::Item::Any
      if target == :str
        raise ArgumentError, "Can't use Any in a string context" # A linter could find this!
      elsif target == :par
        i.data.map(&:data)
      elsif target == :re
        case i.value
        when Array
          data = i.data.map { |j| compile_item(j, doc, target) }
          "(?:"+data.join("|")+")"
        when String
          "[#{Regexp.escape(i.value)}]"
        when Range
          "[#{Regexp.escape(i.value.first)}-#{Regexp.escape(i.value.last)}]"
        end
      end
    end
  end

  def load
    if !defined?(Interscript::Maps) || !Interscript::Maps.has_map?(@map.name)
      @map.dependencies.each do |dep|
        dep = dep.full_name
        if !defined?(Interscript::Maps) || !Interscript::Maps.has_map?(dep)
          Interscript.load(dep, compiler: self.class).load
        end
      end
      eval(@code, $main_binding)
    end
  end

  def call(str, stage=:main)
    load
    Interscript::Maps.transcribe(@map.name, str, stage)
  end
end
