class Interscript::Compiler::Javascript < Interscript::Compiler
  def compile(map)
    @code = File.read(__dir__+"/../../../../js/stdlib.js")
    @code += "function(s) {"
    @code += "var a = JSON.parse(JSON.stringify(is_stdlib_aliases));" # Create a deep clone

    map.aliases.each do |a|
      @code += "a[#{a.name}] = #{a.data.data};"
    end

    map.stage.children.each do |s|
      if Interscript::Node::Group::Parallel === s
        s.children.each do |t|
          @code += "s = s.replace(/#{t.from.data}/g, '#{t.to.data}');"
        end
      else
        @code += "s = s.replace(/#{s.from.data}/g, '#{s.to.data}');"
      end
    end

    @code += "return s; }"
  end

  def call
    # ExecJS thing
    # Also load the runtime (stdlib)
    raise NotImplementedError
  end
end
