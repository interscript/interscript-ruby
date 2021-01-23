$main_binding = binding

class Interscript::Compiler::Ruby < Interscript::Compiler
  def compile(map, stage=:main)
    @map = map
    stage = @map.stages[stage]
    @parallel_trees = {}
    @code = compile_rule(stage, @map, true)
  end

  def compile_rule(r, map = @map, wrapper = false)
    c = ""
    case r
    when Interscript::Node::Stage
      if wrapper
        c = "require 'interscript/stdlib'\n"
        c += "if !defined?(Interscript::Maps); module Interscript; module Maps\n"
        c += "module Cache; end\n"
        c += "@maps = {}\n"
        c += "def self.has_map?(name);         @maps.include?(name); end\n"
        c += "def self.add_map(name,&block);   @maps[name] = block; end\n"
        c += "def self.transcribe(map,string); @maps[map].(string); end\n"
        c += "end; end; end\n"
        c += "Interscript::Maps.add_map \"#{@map.name}\" do |s|\n"
        c += "s = s.dup\n"
      end
      r.children.each do |t|
        c += compile_rule(t, map)
      end
      if wrapper
        c += "s\n"
        c += "end\n"

        @parallel_trees.each do |k,v|
          c += "Interscript::Maps::Cache::PTREE_#{k} ||= #{v.inspect}\n"
        end
      end
    when Interscript::Node::Group::Parallel
      h = {}
      r.children.each do |i|
        raise ArgumentError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i
        raise ArgumentError, "Can't parallelize rules with :before" if i.before
        raise ArgumentError, "Can't parallelize rules with :after" if i.after
        raise ArgumentError, "Can't parallelize rules with :not_before" if i.not_before
        raise ArgumentError, "Can't parallelize rules with :not_after" if i.not_after

        h[compile_item(i.from, map, :par)] = compile_item(i.to, map, :par)
      end
      hh = h.hash.abs
      unless @parallel_trees.include? hh
        tree = Interscript::Stdlib.parallel_replace_compile_tree(h)
        @parallel_trees[hh] = tree
      end
      c += "s = Interscript::Stdlib.parallel_replace_tree(s, Interscript::Maps::Cache::PTREE_#{hh})\n"
    when Interscript::Node::Rule::Sub
      from = Regexp.new(build_regexp(r, map)).inspect
      to = compile_item(r.to, map, :str)
      c += "s.gsub!(#{from}, #{to})\n"
    when Interscript::Node::Rule::Funcall
      c += "s = Interscript::Stdlib::Functions.#{r.name}(s, #{r.kwargs.inspect[1..-2]})\n"
    when Interscript::Node::Rule::Run
      if r.stage.map
        doc = map.dep_aliases[r.stage.map].document
        stage = doc.imported_stages[r.stage.name]
        c += compile_rule(stage, doc)
      else
        stage = map.imported_stages[r.stage.name]
        c += compile_rule(stage, map)
      end
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
    out = case i
    when Interscript::Node::Item::Alias
      if i.map
        d = doc.dep_aliases[i.map].document
        a = d.imported_aliases[i.name]
        raise ArgumentError, "Alias #{i.name} of #{i.stage.map} not found" unless a
        compile_item(a.data, d, target)
      elsif Interscript::Stdlib::ALIASES.include?(i.name)
        if target != :re && Interscript::Stdlib.re_only_alias?(i.name)
          raise ArgumentError, "Can't use #{i.name} in a #{target} context"
        end

        if target == :str
          "::Interscript::Stdlib::ALIASES[#{i.name.inspect}]"
        elsif target == :re
          "\#{::Interscript::Stdlib::ALIASES[#{i.name.inspect}]}"
        elsif target == :par
          raise NotImplementedError, "Can't use aliases in parallel mode yet"
        end
      else
        a = doc.imported_aliases[i.name]
        raise ArgumentError, "Alias #{i.name} not found" unless a
        compile_item(a.data, doc, target)
      end
    when Interscript::Node::Item::String
      if target == :str
        "\"#{i.data}\""
      elsif target == :par
        i.data
      elsif target == :re
        Regexp.escape(i.data)
      end
    when Interscript::Node::Item::Group
      if target == :par
        raise NotImplementedError, "Can't concatenate in parallel mode yet"
      else
        i.children.map { |j| compile_item(j, doc, target) }.join
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

  def call(str, stage=:main)
    raise ArgumentError, "Calling other stages than :main is not supported for Compiler::Ruby" unless stage == :main

    if !defined?(Interscript::Maps) || !Interscript::Maps.has_map?(@map.name)
      eval(@code, $main_binding)
    end

    Interscript::Maps.transcribe(@map.name, str)
  end
end
