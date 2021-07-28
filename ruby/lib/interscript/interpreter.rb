class Interscript::Interpreter < Interscript::Compiler
  attr_accessor :map
  def compile(map, _:nil)
    @map = map
    self
  end

  def call(str, stage=:main, each: false, &block)
    stage = @map.stages[stage]
    s =
    if each
      e = Enumerator.new do |yielder|
        options = []
        options_set = false
        choices = nil

        i = 0

        loop do
          result = nil

          f = Fiber.new do
            $select_nth_string = true
            result = Stage.new(@map, str).execute_rule(stage)
            $select_nth_string = false
            Fiber.yield(:end)
          end

          iter = 0

          loop do
            break if f.resume == :end
            # hash is unused for now... some problems may arise in certain
            # scenarios that are not a danger right now, but i'm genuinely
            # unsure how it can be handled.
            #
            # This scenario is described in a commented out test.
            type, value, hash = f.resume
            if options_set
              f.resume(choices[i][iter])
            else
              options[iter] = value
              f.resume(0)
            end
            iter += 1
          end

          unless options_set
            options_set = true

            opts = options.map { |i| (0...i).to_a }
            choices = opts[0].product(*opts[1..-1])
          end

          yielder.yield(result)

          i += 1
          break if i == choices.length
        end
      end

      if block_given?
        e.each(&block)
      else
        e
      end
    else
      Stage.new(@map, str).execute_rule(stage)
    end
  end

  class Stage
    def initialize(map, str)
      @str = str
      @map = map
    end

    def execute_rule r
      return if r.reverse_run == true
      case r
      when Interscript::Node::Group::Parallel
        if r.cached_tree
          @str = Interscript::Stdlib.parallel_replace_tree(@str, r.cached_tree)
        elsif r.subs_regexp && r.subs_replacements
          if $DEBUG_RE
            @str = Interscript::Stdlib.parallel_regexp_gsub_debug(@str, r.subs_regexp, r.subs_replacements)
          else
            @str = Interscript::Stdlib.parallel_regexp_gsub(@str, r.subs_regexp, r.subs_replacements)
          end
        else
          begin
            # Try to build a tree
            subs_array = []
            r.children.each do |i|
              raise ArgumentError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i
              raise ArgumentError, "Can't parallelize rules with :before" if i.before
              raise ArgumentError, "Can't parallelize rules with :after" if i.after
              raise ArgumentError, "Can't parallelize rules with :not_before" if i.not_before
              raise ArgumentError, "Can't parallelize rules with :not_after" if i.not_after
              subs_array << [build_item(i.from, :par), build_item(i.to, :parstr)]
            end
            tree = Interscript::Stdlib.parallel_replace_compile_tree(subs_array) #.sort_by{|k,v| -k.length})
            @str = Interscript::Stdlib.parallel_replace_tree(@str, tree)
            r.cached_tree = tree
            # $using_tree = true
          rescue
            # $using_tree = false
            # Otherwise let's build a megaregexp
            subs_array = []
            Interscript::Stdlib.deterministic_sort_by_max_length(r.children).each do |i|  # rule.from.max_length gives somewhat better test results, why is that
              raise ArgumentError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i

              subs_array << [build_regexp(i), build_item(i.to, :parstr)]
            end
            r.subs_regexp = Interscript::Stdlib.parallel_regexp_compile(subs_array)
            r.subs_replacements = subs_array.map(&:last)
            if $DEBUG_RE
              # puts subs_array.inspect
              $subs_array = subs_array
              @str = Interscript::Stdlib.parallel_regexp_gsub_debug(@str, r.subs_regexp, r.subs_replacements)
            else
              @str = Interscript::Stdlib.parallel_regexp_gsub(@str, r.subs_regexp, r.subs_replacements)
            end
          end
        end
      when Interscript::Node::Group
        r.children.each do |t|
          execute_rule(t)
        end
      when Interscript::Node::Rule::Sub
        if r.to == :upcase
          @str = @str.gsub(Regexp.new(build_regexp(r)), &:upcase)
        elsif r.to == :downcase
          @str = @str.gsub(Regexp.new(build_regexp(r)), &:downcase)
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
      i = i.nth_string if %i[str parstr].include? target
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
          i.children.map do |j|
            build_item(j, target, doc)
          end.reduce([""]) do |j,k|
            Array(j).product(Array(k)).map(&:join)
          end
        else
          i.children.map { |j| build_item(j, target, doc) }.join
        end
      when Interscript::Node::Item::CaptureGroup
        if target == :par
          raise ArgumentError, "Can't use a CaptureGroup in a #{target} context"
        end
        "(" + build_item(i.data, target, doc) + ")"
      when Interscript::Node::Item::Maybe,
           Interscript::Node::Item::MaybeSome,
           Interscript::Node::Item::Some

        resuffix = { Interscript::Node::Item::Maybe     => "?" ,
                     Interscript::Node::Item::Some      => "+" ,
                     Interscript::Node::Item::MaybeSome => "*" }[i.class]

        if target == :par
          raise ArgumentError, "Can't use a MaybeSome in a #{target} context"
        end
        if Interscript::Node::Item::String === i.data && i.data.data.length != 1
          "(?:" + build_item(i.data, target, doc) + ")" + resuffix
        else
          build_item(i.data, target, doc) + resuffix
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
