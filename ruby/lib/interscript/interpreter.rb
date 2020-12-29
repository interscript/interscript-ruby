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
        # A hack at this time, it should become a trie.
        r.children.sort_by { |i| -i.from.max_length }.each do |t|
          execute_rule(t)
        end
      when Interscript::Node::Group
        r.children.each do |t|
          execute_rule(t)
        end
      when Interscript::Node::Rule::Sub
        @str = @str.gsub(Regexp.new(build_regexp(r)), build_item(r.to, :str))
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
      out = case i
      when Interscript::Node::Item::Alias
        if i.map
          d = doc.dep_aliases[i.stage.map].document
          a = d.imported_aliases[i.name]
          build_item(a.data, target, d)
        elsif Interscript::Stdlib::ALIASES.include?(i.name)
          if target == :str && Interscript::Stdlib.re_only_alias?(i.name)
            raise ArgumentError, "Can't use #{i.name} in a string context"
          end
          Interscript::Stdlib::ALIASES[i.name]
        else
          a = doc.imported_aliases[i.name]
          build_item(a.data, target, doc)
        end
      when Interscript::Node::Item::String
        if target == :str
          i.data
        elsif target == :re
          Regexp.escape(i.data)
        end
      when Interscript::Node::Item::Group
        i.children.map { |j| build_item(j, target, doc) }.join
      when Interscript::Node::Item::Any
        if target == :str
          raise ArgumentError, "Can't use Any in a string context" # A linter could find this!
        elsif target == :re
          case i.value
          when Array
            data = i.data.map { |j| build_item(j, target, doc) }
            "(?:"+data.join("|").gsub("])|(?:[", '').gsub("]|[", '')+")"
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
