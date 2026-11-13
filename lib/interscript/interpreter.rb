class Interscript::Interpreter < Interscript::Compiler
  attr_accessor :map
  def compile(map, _: nil)
    @map = map
    self
  end

  def call(str, stage = :main, each: false, language: nil, &block)
    stage_name = stage
    stage = @map.stages[stage]
    # WO18 G4 (parity audit): a missing stage used to crash with an
    # accidental NoMethodError (nil flowed into execute_rule). rs's
    # named error is canon.
    raise Interscript::MapLogicError, %(stage "#{stage_name}" not found in #{@map.name}) unless stage
    if each
      e = Enumerator.new do |yielder|
        options = []
        options_set = false
        choices = nil

        i = 0

        loop do
          result = nil

          f = Fiber.new do
            # standard:disable Style/GlobalVars (deliberate $DEBUG / -d-flag debug idiom)
            $select_nth_string = true
            # standard:enable Style/GlobalVars
            result = Stage.new(@map, str, language: language).execute_rule(stage)
            # standard:disable Style/GlobalVars (deliberate $DEBUG / -d-flag debug idiom)
            $select_nth_string = false
            # standard:enable Style/GlobalVars
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
            _, value, _ = f.resume
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
            choices = opts[0].product(*opts[1..])
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
      Stage.new(@map, str, language: language).execute_rule(stage)
    end
  end

  # ISC-WF-1 W3: effective language for a run. A selection outside the
  # map's `languages` declaration (or any selection on a map without a
  # declaration) means every `when` guard is inert (spec §5.1).
  def self.select_language(map, language)
    return nil if language.nil?

    declared = map.languages
    return nil unless declared.is_a?(Interscript::Node::LanguagesDecl) &&
      declared.include?(language.to_sym)

    language.to_sym
  end

  class Stage
    attr_reader :language

    def initialize(map, str, language: nil)
      @str = str
      @map = map
      @language = Interscript::Interpreter.select_language(map, language)
    end

    # ISC-WF-1 W3 guard applicability. Unguarded rules always apply; a
    # guarded rule applies only under a selected language that its `when`
    # list contains. Inert rules are absent from the pass (spec §5.1).
    def guard_applies? rule
      return true unless Interscript::Node::Rule::Sub === rule && rule.when_languages
      return false unless @language

      rule.when_languages.include?(@language)
    end

    # ISC-WF-1 W3: the effective rule set of a parallel pass = unguarded
    # rules ∪ guard-applicable rules; where an unguarded rule and a
    # guard-applicable rule share the same from-string, the
    # guard-applicable rule wins (spec §5.2). Passes without any guard
    # return the group untouched — zero change for pre-WF1 maps. Filtered
    # variants are memoized per selected language on the group so the
    # compiled-tree cache below stays per-language.
    def resolve_parallel_guards r
      return r unless r.children.any? { |c| Interscript::Node::Rule::Sub === c && c.when_languages }

      r.wf1_variants ||= {}
      r.wf1_variants[@language] ||= begin
        applicable = r.children.select { |c| guard_applies?(c) }
        guarded_froms = applicable
          .select { |c| Interscript::Node::Rule::Sub === c && c.when_languages }
          .map { |c| c.from.inspect }
        filtered = Interscript::Node::Group::Parallel.new
        filtered.children = applicable.reject do |c|
          Interscript::Node::Rule::Sub === c && !c.when_languages &&
            guarded_froms.include?(c.from.inspect)
        end
        filtered
      end
    end

    def execute_rule r
      return if r.reverse_run == true
      case r
      when Interscript::Node::Group::Parallel
        r = resolve_parallel_guards(r)
        if r.cached_tree
          @str = Interscript::Stdlib.parallel_replace_tree(@str, r.cached_tree)
        elsif r.subs_regexp && r.subs_replacements
          # standard:disable Style/GlobalVars (deliberate $DEBUG / -d-flag debug idiom)
          @str = if $DEBUG_RE
            # standard:enable Style/GlobalVars
            Interscript::Stdlib.parallel_regexp_gsub_debug(@str, r.subs_regexp, r.subs_replacements)
          else
            Interscript::Stdlib.parallel_regexp_gsub(@str, r.subs_regexp, r.subs_replacements)
          end
        else
          begin
            # Try to build a tree
            subs_array = []
            r.children.each do |i|
              raise Interscript::SystemConversionError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i
              raise Interscript::SystemConversionError, "Can't parallelize rules with :before" if i.before
              raise Interscript::SystemConversionError, "Can't parallelize rules with :after" if i.after
              raise Interscript::SystemConversionError, "Can't parallelize rules with :not_before" if i.not_before
              raise Interscript::SystemConversionError, "Can't parallelize rules with :not_after" if i.not_after
              next if i.reverse_run == true
              subs_array << [build_item(i.from, :par), build_item(i.to, :parstr)]
            end
            tree = Interscript::Stdlib.parallel_replace_compile_tree(subs_array) # .sort_by{|k,v| -k.length})
            @str = Interscript::Stdlib.parallel_replace_tree(@str, tree)
            r.cached_tree = tree
            # $using_tree = true
          rescue
            # $using_tree = false
            # Otherwise let's build a megaregexp
            subs_array = []
            Interscript::Stdlib.deterministic_sort_by_max_length(r.children).each do |i|  # rule.from.max_length gives somewhat better test results, why is that
              raise Interscript::SystemConversionError, "Can't parallelize #{i.class}" unless Interscript::Node::Rule::Sub === i
              next if i.reverse_run == true
              subs_array << [build_regexp(i), build_item(i.to, :parstr)]
            end
            r.subs_regexp = Interscript::Stdlib.parallel_regexp_compile(subs_array)
            r.subs_replacements = subs_array.map(&:last)
            # standard:disable Style/GlobalVars (deliberate $DEBUG / -d-flag debug idiom)
            if $DEBUG_RE
              # standard:enable Style/GlobalVars
              # puts subs_array.inspect
              # standard:disable Style/GlobalVars (deliberate $DEBUG / -d-flag debug idiom)
              $subs_array = subs_array
              # standard:enable Style/GlobalVars
              @str = Interscript::Stdlib.parallel_regexp_gsub_debug(@str, r.subs_regexp, r.subs_replacements)
            else
              @str = Interscript::Stdlib.parallel_regexp_gsub(@str, r.subs_regexp, r.subs_replacements)
            end
          end
        end
      when Interscript::Node::Group
        r.children.each do |t|
          # ISC-WF-1 W3: in sequence, an inert guarded rule is skipped.
          next unless guard_applies?(t)
          execute_rule(t)
        end
      when Interscript::Node::Rule::Sub
        return @str unless guard_applies?(r)
        @str = if r.to == :upcase
          @str.gsub(Regexp.new(build_regexp(r)), &:upcase)
        elsif r.to == :downcase
          @str.gsub(Regexp.new(build_regexp(r)), &:downcase)
        else
          @str.gsub(Regexp.new(build_regexp(r)), build_item(r.to, :str))
        end
      when Interscript::Node::Rule::Funcall
        @str = Interscript::Stdlib::Functions.public_send(r.name, @str, **r.kwargs)
      when Interscript::Node::Rule::Run
        # WO18 G4 (parity audit): a missing run-target stage used to
        # crash with `NoMethodError undefined method 'reverse_run' for
        # nil`; raise the named error instead (rs canon).
        if r.stage.map
          doc = @map.dep_aliases[r.stage.map].document
          stage = doc.imported_stages[r.stage.name]
          raise Interscript::MapLogicError, %(stage "#{r.stage.name}" not found in #{doc.name}) unless stage
          @str = Stage.new(doc, @str, language: @language).execute_rule(stage)
        else
          stage = @map.imported_stages[r.stage.name]
          raise Interscript::MapLogicError, %(stage "#{r.stage.name}" not found in #{@map.name}) unless stage
          @str = Stage.new(@map, @str, language: @language).execute_rule(stage)
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

    def build_item i, target = nil, doc = @map
      i = i.nth_string if %i[str parstr].include? target
      i = Interscript::Node::Item.try_convert(i)
      target = :par if target == :parstr

      case i
      when Interscript::Node::Item::Alias
        if i.map
          d = doc.dep_aliases[i.map].document
          a = d.imported_aliases[i.name]
          raise Interscript::SystemConversionError, "Alias #{i.name} of #{i.stage.map} not found" unless a
          build_item(a.data, target, d)
        elsif Interscript::Stdlib::ALIASES.include?(i.name)
          if target != :re && Interscript::Stdlib.re_only_alias?(i.name)
            raise Interscript::SystemConversionError, "Can't use #{i.name} in a #{target} context"
          end
          Interscript::Stdlib::ALIASES[i.name]
        else
          a = doc.imported_aliases[i.name]
          raise Interscript::SystemConversionError, "Alias #{i.name} not found" unless a
          build_item(a.data, target, doc)
        end
      when Interscript::Node::Item::String
        if [:str, :par].include? target
          i.data
        else # if target == :re
          Regexp.escape(i.data)
        end
      when Interscript::Node::Item::Group
        if target == :par
          i.children.map do |j|
            build_item(j, target, doc)
          end.reduce([""]) do |j, k|
            Array(j).product(Array(k)).map(&:join)
          end
        else
          i.children.map { |j| build_item(j, target, doc) }.join
        end
      when Interscript::Node::Item::CaptureGroup
        if target == :par
          raise Interscript::SystemConversionError, "Can't use a CaptureGroup in a #{target} context"
        end
        "(" + build_item(i.data, target, doc) + ")"
      when Interscript::Node::Item::Maybe,
           Interscript::Node::Item::MaybeSome,
           Interscript::Node::Item::Some

        resuffix = {Interscript::Node::Item::Maybe => "?",
                    Interscript::Node::Item::Some => "+",
                    Interscript::Node::Item::MaybeSome => "*"}[i.class]

        if target == :par
          raise Interscript::SystemConversionError, "Can't use a MaybeSome in a #{target} context"
        end
        if Interscript::Node::Item::String === i.data && i.data.data.length != 1
          "(?:" + build_item(i.data, target, doc) + ")" + resuffix
        else
          build_item(i.data, target, doc) + resuffix
        end
      when Interscript::Node::Item::CaptureRef
        if target == :par
          raise Interscript::SystemConversionError, "Can't use CaptureRef in parallel mode"
        end
        "\\#{i.id}"
      when Interscript::Node::Item::Any
        if target == :str
          # We may never reach this point
          raise Interscript::SystemConversionError, "Can't use Any in a string context"
        elsif target == :par
          i.data.map(&:data)
        elsif target == :re
          case i.value
          when Array
            data = i.data.map { |j| build_item(j, target, doc) }
            "(?:" + data.join("|") + ")"
          when String
            "[#{Regexp.escape(i.value)}]"
          when Range
            "[#{Regexp.escape(i.value.first)}-#{Regexp.escape(i.value.last)}]"
          end
        end
      end
    end
  end
  # standard:disable Layout/TrailingEmptyLines (deliberate)
end
# standard:enable Layout/TrailingEmptyLines
