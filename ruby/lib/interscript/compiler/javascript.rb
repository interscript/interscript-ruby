class Interscript::Compiler::Javascript < Interscript::Compiler
  def compile(map)
    @code = File.read(__dir__+"/../../../../js/stdlib.js")
    @code += "function(s) {"
    @code += "var a = JSON.parse(JSON.stringify(is_stdlib_aliases));" # Create a deep clone

    map.aliases.each do |a|
      @code += "a.#{a.name} = #{compile_item(a.data, :str)};"
    end

    compile_rule(map.stages[:main], map)

    @code = @code.gsub(';s = s.replace', '.replace')

    @code += "return s; }"
  end

  def compile_rule(r, map)
    case r
    when Interscript::Node::Group
      r.children.each do |t|
        compile_rule(t, map)
      end
    when Interscript::Node::Rule::Sub
      @code += "s = s.replace(#{compile_item(r.from, :re)}, #{compile_item(r.to, :str)});"
    when Interscript::Node::Rule::Run
      # Not implemented
    end
  end

  def compile_item i, target=nil
    out = case i
    when Interscript::Node::Item::Alias
      "\"+a.#{i.name}+\""
    when Interscript::Node::Item::String
      "#{i.data}"
    when Interscript::Node::Item::Group
      i.children.map { |j| compile_item(j) }.join
    when Interscript::Node::Item::Any
      "(" + i.data.map { |j| compile_item(j) }.join("|") + ")"
    end

    case target
    when :re
      "new RegExp(\"#{out}\", \"g\")"
    when :str
      "\"#{out}\""
    else
      out
    end
  end

  def call
    # ExecJS thing
    # Also load the runtime (stdlib)
    raise NotImplementedError
  end
end
