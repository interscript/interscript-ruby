require 'pycall'

class Interscript::Compiler::Python < Interscript::Compiler
  def escape(val)
    case val
    when String, Integer
      val.inspect
    when Symbol
      val.to_s.inspect
    when Hash
      "{"+
        val.map { |k,v| "#{escape k}:#{escape v}" }.join(",")+
      "}"
    when Array
      "[" + val.map { |i| escape i }.join(",") + "]"
    when nil
      "None"
    else
      pp [:error, val]
      exit!
    end
  end

  def re_escape(val)
    @pycall_regex ||= PyCall.import_module("regex")
    @pycall_regex.escape(val).gsub("\\", "\\\\\\\\").gsub('"', "\\\\\"")
  end

  def new_regexp(str)
    "re.compile(\"#{str}\", re.MULTILINE)"
  end

  def indent
    @indent += 4
    yield
    @indent -= 4
  end

  def emit(code)
    @code << (" " * @indent) << code << "\n"
    code
  end

  def compile(map, debug: false)
    @indent = 0
    @map = map
    @debug = debug
    @parallel_trees = {}
    @parallel_regexps = {}
    @code = ""
    emit "import interscript"
    emit "import regex as re"
    map.dependencies.map(&:full_name).each do |dep|
      emit "interscript.load_map(#{escape dep})"
    end

    emit "interscript.stdlib.define_map(#{escape map.name})"

    map.aliases.each do |name, value|
      val = compile_item(value.data, map, :str)
      emit "interscript.stdlib.add_map_alias(#{escape map.name}, #{escape name}, #{val})"
      val = "\"" + compile_item(value.data, map, :re) + "\""
      emit "interscript.stdlib.add_map_alias_re(#{escape map.name}, #{escape name}, #{val})"
    end

    map.stages.each do |_, stage|
      compile_rule(stage, @map, true)
    end
    @parallel_trees.each do |k,v|
      emit "_PTREE_#{k} = #{escape v}"
    end
    @parallel_regexps.each do |k,v|
      v = %{["#{v[0]}", #{escape v[1]}]}
      emit "_PRE_#{k} = #{v}"
    end
  end

  def parallel_regexp_compile(subs_hash)
    # puts subs_hash.inspect
    regexp = subs_hash.each_with_index.map do |p,i|
      "(?P<_%d>%s)" % [i,p[0]]
    end.join("|")
    subs_regexp = regexp
    # puts subs_regexp.inspect
  end

  def compile_rule(r, map = @map, wrapper = false)
    return if r.reverse_run == true
    case r
    when Interscript::Node::Stage
      if @debug
        emit "if not hasattr(interscript, 'map_debug'):"
        indent { emit "interscript.map_debug = []" }
      end
      emit "def _stage_#{r.name}(s):"
      indent do
        r.children.each do |t|
          comp = compile_rule(t, map)
          emit %{interscript.map_debug.append([s, #{escape @map.name.to_s}, #{escape r.name.to_s}, #{escape t.inspect}, #{escape comp}])} if @debug
        end
        emit "return s\n"
      end
      emit "interscript.stdlib.add_map_stage(#{escape @map.name}, #{escape r.name}, _stage_#{r.name})"
    when Interscript::Node::Group::Parallel
      begin
        # Try to build a tree
        a = []
        r.children.each do |i|
          raise Interscript::SystemConversionError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i
          raise Interscript::SystemConversionError, "Can't parallelize rules with :before" if i.before
          raise Interscript::SystemConversionError, "Can't parallelize rules with :after" if i.after
          raise Interscript::SystemConversionError, "Can't parallelize rules with :not_before" if i.not_before
          raise Interscript::SystemConversionError, "Can't parallelize rules with :not_after" if i.not_after

          next if i.reverse_run == true
          a << [compile_item(i.from, map, :par), compile_item(i.to, map, :parstr)]
        end
        ah = a.hash.abs
        unless @parallel_trees.include? ah
          tree = Interscript::Stdlib.parallel_replace_compile_tree(a)
          @parallel_trees[ah] = tree
        end
        emit "s = interscript.stdlib.parallel_replace_tree(s, _PTREE_#{ah})"
      rescue
        # Otherwise let's build a megaregexp
        a = []
        Interscript::Stdlib.deterministic_sort_by_max_length(r.children).each do |i|
          raise Interscript::SystemConversionError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i

          next if i.reverse_run == true
          a << [build_regexp(i, map), compile_item(i.to, map, :parstr)]
        end
        ah = a.hash.abs
        unless @parallel_regexps.include? ah
          re = parallel_regexp_compile(a)
          @parallel_regexps[ah] = [re, a.map(&:last)]
        end
        emit "s = interscript.stdlib.parallel_regexp_gsub(s, *_PRE_#{ah})"
      end
    when Interscript::Node::Rule::Sub
      from = new_regexp build_regexp(r, map)
      if r.to == :upcase
        to = 'interscript.stdlib.upper'
      elsif r.to == :downcase
        to = 'interscript.stdlib.lower'
      else
        to = compile_item(r.to, map, :str)
      end
      emit "s = #{from}.sub(#{to}, s)"
    when Interscript::Node::Rule::Funcall
      emit "s = interscript.functions.#{r.name}(s, #{escape r.kwargs})"
    when Interscript::Node::Rule::Run
      if r.stage.map
        doc = map.dep_aliases[r.stage.map].document
        stage = doc.imported_stages[r.stage.name]
      else
        stage = map.imported_stages[r.stage.name]
      end
      emit "s = interscript.transliterate(#{escape stage.doc_name}, s, #{escape stage.name})"
    else
      raise Interscript::SystemConversionError, "Can't compile unhandled #{r.class}"
    end
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
    if target == :parstr
      parstr = true
      target = :par
    end

    out = case i
    when Interscript::Node::Item::Alias
      astr = if i.map
        d = doc.dep_aliases[i.map].document
        a = d.imported_aliases[i.name]
        raise Interscript::SystemConversionError, "Alias #{i.name} of #{i.stage.map} not found" unless a
        "interscript.stdlib.get_alias_ALIASTYPE(#{escape a.doc_name}, #{escape a.name})"
      elsif Interscript::Stdlib::ALIASES.include?(i.name)
        if target != :re && Interscript::Stdlib.re_only_alias?(i.name)
          raise Interscript::SystemConversionError, "Can't use #{i.name} in a #{target} context"
        end
        stdlib_alias = true
        "interscript.stdlib.aliases[#{escape i.name}]"
      else
        a = doc.imported_aliases[i.name]
        raise Interscript::SystemConversionError, "Alias #{i.name} not found" unless a

        "interscript.stdlib.get_alias_ALIASTYPE(#{escape a.doc_name}, #{escape a.name})"
      end

      if target == :str
        astr = astr.sub("_ALIASTYPE(", "(")
      elsif target == :re
        astr = "\"+#{astr.sub("_ALIASTYPE(", "_re(")}+\""
      elsif parstr && stdlib_alias
        astr = Interscript::Stdlib::ALIASES[i.name]
      elsif target == :par
        # raise NotImplementedError, "Can't use aliases in parallel mode yet"
        astr = Interscript::Stdlib::ALIASES[i.name]
      end
    when Interscript::Node::Item::String
      if target == :str
        # Replace \1 with \\1, this is weird, but it works!
        i.data.gsub("\\", "\\\\\\\\").inspect
      elsif target == :par
        i.data
      elsif target == :re
        re_escape(i.data)
      end
    when Interscript::Node::Item::Group
      if target == :par
        i.children.map do |j|
          compile_item(j, doc, target)
        end.reduce([""]) do |j,k|
          Array(j).product(Array(k)).map(&:join)
        end
      elsif target == :str
        i.children.map { |j| compile_item(j, doc, target) }.join("+")
      elsif target == :re
        i.children.map { |j| compile_item(j, doc, target) }.join
      end
    when Interscript::Node::Item::CaptureGroup
      if target != :re
        raise Interscript::SystemConversionError, "Can't use a CaptureGroup in a #{target} context"
      end
      "(" + compile_item(i.data, doc, target) + ")"
    when Interscript::Node::Item::Maybe,
         Interscript::Node::Item::MaybeSome,
         Interscript::Node::Item::Some

      resuffix = { Interscript::Node::Item::Maybe     => "?" ,
                   Interscript::Node::Item::Some      => "+" ,
                   Interscript::Node::Item::MaybeSome => "*" }[i.class]

      if target == :par
        raise Interscript::SystemConversionError, "Can't use a Maybe in a #{target} context"
      end
      if Interscript::Node::Item::String === i.data && i.data.data.length != 1
        "(?:" + compile_item(i.data, doc, target) + ")" + resuffix
      else
        compile_item(i.data, doc, target) + resuffix
      end
    when Interscript::Node::Item::CaptureRef
      if target == :par
        raise Interscript::SystemConversionError, "Can't use CaptureRef in parallel mode"
      elsif target == :re
        "\\\\#{i.id}"
      elsif target == :str
        "\"\\\\#{i.id}\""
      end
    when Interscript::Node::Item::Any
      if target == :str
        raise Interscript::SystemConversionError, "Can't use Any in a string context" # A linter could find this!
      elsif target == :par
        i.data.map(&:data)
      elsif target == :re
        case i.value
        when Array
          data = i.data.map { |j| compile_item(j, doc, target) }
          "(?:"+data.join("|")+")"
        when String
          "[#{re_escape(i.value)}]"
        when Range
          "[#{re_escape(i.value.first)}-#{re_escape(i.value.last)}]"
        end
      end
    end
  end

  @maps_loaded = {}
  @ctx = nil
  class << self
    attr_accessor :maps_loaded
    attr_accessor :ctx
  end

  def load
    if !self.class.maps_loaded[@map.name]
      @map.dependencies.each do |dep|
        dep = dep.full_name
        if !self.class.maps_loaded[dep]
          Interscript.load(dep, compiler: self.class).load
        end
      end

      ctx = self.class.ctx
      python_src_path = File.join(__dir__, '..', '..', '..', '..', 'python', 'src')
      unless ctx
        PyCall.sys.path.append(python_src_path)
        self.class.ctx = PyCall.import_module("interscript")
      end
      #puts @code
      File.write("#{python_src_path}/interscript/maps/#{@map.name}.py", @code)
      self.class.ctx.load_map(@map.name)

      self.class.maps_loaded[@map.name] = true
    end
  end

  def call(str, stage=:main)
    load
    self.class.ctx.transliterate(@map.name, str, stage.to_s)
  end

  def self.read_debug_data
    (ctx['map_debug'] || []).map(&:to_a).to_a
  end

  def self.reset_debug_data
    ctx['map_debug'].clear
  end
end
