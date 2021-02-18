class Interscript::Interpreter < Interscript::Compiler
  def compile(map)
    @map = map
    self
  end

  def call(str, stage=:main)
    stage = @map.stages[stage]
    Stage.new(@map, str).execute_rule(stage)
  end

  class Stage
    def initialize(map, str)
      @str = str
      @map = map
    end

    def execute_rule r
      case r
      when Interscript::Node::Group::Parallel
        if r.cached_tree
          @str = Interscript::Stdlib.parallel_replace_tree(@str, r.cached_tree)
        else
          a = []
          r.children.each do |i|
            raise ArgumentError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i
            raise ArgumentError, "Can't parallelize rules with :before" if i.before
            raise ArgumentError, "Can't parallelize rules with :after" if i.after
            raise ArgumentError, "Can't parallelize rules with :not_before" if i.not_before
            raise ArgumentError, "Can't parallelize rules with :not_after" if i.not_after

            a << [build_item(i.from, :par), build_item(i.to, :parstr)]
          end
          r.cached_tree = Interscript::Stdlib.parallel_replace_compile_tree(a)
          @str = Interscript::Stdlib.parallel_replace_tree(@str, r.cached_tree)
        end
      when Interscript::Node::Group
        r.children.each do |t|
          execute_rule(t)
        end
      when Interscript::Node::Rule::Sub
        if r.to == :upcase
          @str = @str.gsub(Regexp.new(build_regexp(r)), &:upcase)
        else
          @str = @str.gsub(Regexp.new(build_regexp(r)), build_item(r.to, :str))
        end
      when Interscript::Node::Rule::Funcall
        @str = Interscript::Stdlib::Functions.public_send(r.name, @str, **r.kwargs)
      when Interscript::Node::Rule::Run
        if r.stage.map
          doc = @map.dep_aliases[r.stage.map].document
          stage = doc.imported_stages[r.stage.name]
          @str = Stage.new(doc, @str).execute_rule(stage)
        else
          stage = @map.imported_stages[r.stage.name]
          @str = Stage.new(@map, @str).execute_rule(stage)
        end
      end

      @str
    end

    def build_regexp(r)
      from = build_item(r.from, :re)
      before = build_item(r.before, :re) if r.before
      after = build_item(r.after, :re) if r.after
      not_before = build_item(r.not_before, :re) if r.not_before
      not_after = build_item(r.not_after, :re) if r.not_after

      re = ""
      re += "(?<=#{before})" if before
      re += "(?<!#{not_before})" if not_before
      re += from
      re += "(?!#{not_after})" if not_after
      re += "(?=#{after})" if after
      re
    end

    def build_item i, target=nil, doc=@map
      i = i.first_string if %i[str parstr].include? target
      i = Interscript::Node::Item.try_convert(i)
      target = :par if target == :parstr

      out = case i
      when Interscript::Node::Item::Alias
        if i.map
          d = doc.dep_aliases[i.map].document
          a = d.imported_aliases[i.name]
          raise ArgumentError, "Alias #{i.name} of #{i.stage.map} not found" unless a
          build_item(a.data, target, d)
        elsif Interscript::Stdlib::ALIASES.include?(i.name)
          if target != :re && Interscript::Stdlib.re_only_alias?(i.name)
            raise ArgumentError, "Can't use #{i.name} in a #{target} context"
          end
          Interscript::Stdlib::ALIASES[i.name]
        else
          a = doc.imported_aliases[i.name]
          raise ArgumentError, "Alias #{i.name} not found" unless a
          build_item(a.data, target, doc)
        end
      when Interscript::Node::Item::String
        if [:str, :par].include? target
          i.data
        else#if target == :re
          Regexp.escape(i.data)
        end
      when Interscript::Node::Item::Group
        if target == :par
          raise NotImplementedError, "Can't concatenate in parallel mode yet"
        else
          i.children.map { |j| build_item(j, target, doc) }.join
        end
      when Interscript::Node::Item::CaptureGroup
        if target == :par
          raise ArgumentError, "Can't use a CaptureGroup in a #{target} context"
        end
        "(" + build_item(i.data, target, doc) + ")"
      when Interscript::Node::Item::Maybe
        if target == :par
          raise ArgumentError, "Can't use a Maybe in a #{target} context"
        end
        if Interscript::Node::Item::String === i.data
          "(?:" + build_item(i.data, target, doc) + ")?"
        else
          build_item(i.data, target, doc) + "?"
        end
      when Interscript::Node::Item::CaptureRef
        if target == :par
          raise ArgumentError, "Can't use CaptureRef in parallel mode"
        end
        "\\#{i.id}"
      when Interscript::Node::Item::Any
        if target == :str
          # We may never reach this point
          raise ArgumentError, "Can't use Any in a string context"
        elsif target == :par
          i.data.map(&:data)
        elsif target == :re
          case i.value
          when Array
            data = i.data.map { |j| build_item(j, target, doc) }
            "(?:"+data.join("|")+")"
          when String
            "[#{Regexp.escape(i.value)}]"
          when Range
            "[#{Regexp.escape(i.value.first)}-#{Regexp.escape(i.value.last)}]"
          end
        end
      end
    end
  end
end
