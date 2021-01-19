class Interscript::Compiler::Ruby < Interscript::Compiler
  def compile(map, stage=:main)
    @map = map
    @loaded = false
    stage = @map.stages[stage]
    @code = compile_rule(stage, true)
  end
  def compile_rule(r, wrapper = false)
    c = ""
    case r
    when Interscript::Node::Stage
      if wrapper
      c = "if !defined?(Interscript::Maps); module Interscript; module Interscript::Maps\n"
      c += "@@maps = {}\n"
      c += "def self.add_map(name,proc);     @@maps[name] = proc; end\n"
      c += "def self.transcribe(map,string); @@maps[map].call(string); end\n"
      c += "end;end;end\n"
      c += "Interscript::Maps.add_map(\"#{@map.name}\", Proc.new{|s| \n"
      end
      r.children.each do |t|
        c += compile_rule(t)
      end
      c += "s })" if wrapper
    when Interscript::Node::Group::Parallel
      r.children.sort_by{|i| -i.from.max_length }.each do |t|
        c += compile_rule(t)
      end
    when Interscript::Node::Rule::Sub
      from = Regexp.new(build_regexp(r)).inspect
      to = compile_item(r.to, :str)
      c += "s = s.gsub(#{from}, #{to})\n"
    when Interscript::Node::Rule::Run
      if r.stage.map
        doc = @map.dep_aliases[r.stage.map].document
        stage = doc.imported_stages[r.stage.name]
        c += compile_rule(stage)
      else
        stage = @map.imported_stages[r.stage.name]
        c += compile_rule(stage)
      end
    end
    c
  end

  def build_regexp(r)
    from = compile_item(r.from, :re)
    before = compile_item(r.before, :re) if r.before
    after = compile_item(r.after, :re) if r.after
    not_before = compile_item(r.not_before, :re) if r.not_before
    not_after = compile_item(r.not_after, :re) if r.not_after

    re = ""
    re += "(?<=#{before})" if before
    re += "(?<!#{not_before})" if not_before
    re += from
    re += "(?!#{not_after})" if not_after
    re += "(?=#{after})" if after
    re
  end

  def compile_item i, target=nil, doc=@map
    out = case i
    when Interscript::Node::Item::Alias
      if i.map
        d = doc.dep_aliases[i.stage.map].document
        a = d.imported_aliases[i.name]
        compile_item(a.data, target, d)
      elsif Interscript::Stdlib::ALIASES.include?(i.name)
        if target == :str && Interscript::Stdlib.re_only_alias?(i.name)
          raise ArgumentError, "Can't use #{i.name} in a string context"
        end
        Interscript::Stdlib::ALIASES[i.name]
      else
        a = doc.imported_aliases[i.name]
        compile_item(a.data, target, doc)
      end
    when Interscript::Node::Item::String
      if target == :str
        "\"#{i.data}\""
      elsif target == :re
        Regexp.escape(i.data)
      end
    when Interscript::Node::Item::Group
      i.children.map { |j| compile_item(j, target, doc) }.join
    when Interscript::Node::Item::Any
      if target == :str
        raise ArgumentError, "Can't use Any in a string context" # A linter could find this!
      elsif target == :re
        case i.value
        when Array
          data = i.data.map { |j| compile_item(j, target, doc) }
          "(?:"+data.join("|").gsub("])|(?:[", '').gsub("]|[", '')+")"
        when String
          "[#{Regexp.escape(i.value)}]"
        when Range
          "[#{Regexp.escape(i.value.first)}-#{Regexp.escape(i.value.last)}]"
        end
      end
    end
  end

  def call(str)
    if !@loaded
      eval(@code)
    end

    Interscript::Maps.transcribe(@map.name, str)
  end
end
