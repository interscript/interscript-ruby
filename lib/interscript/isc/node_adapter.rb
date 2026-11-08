# frozen_string_literal: true

module Interscript
  module Isc
    # Bridges the ISC document hash (from DocumentBuilder) to the existing
    # Interscript::Node::Document object model, enabling .isc files to be
    # used for actual transliteration via the standard runtime.
    #
    # This is the critical integration point: without it, ISC files can be
    # parsed but cannot transliterate.
    #
    #   doc_hash = Interscript::Isc::DocumentBuilder.build(tree)
    #   node_doc = Interscript::Isc::NodeAdapter.to_interscript_node(doc_hash)
    #   Interscript.transliterate_node(node_doc, "main", "hello")
    #
    class NodeAdapter
      def self.to_interscript_node(isc_doc)
        new(isc_doc).build
      end

      def initialize(isc_doc)
        @isc_doc = isc_doc
        @imported = {}
        # Local alias name -> raw value fragment, for set/constraint
        # charset resolution (grek_latn_any = any([grek_any, …])).
        @local_raw = Array(isc_doc[:aliases]).to_h { |a| [a[:name].to_sym, a[:value]] }
        @charset_cache = {}
        @resolving = []
        # ISC-WF-1 W1: memoized fully-expanded rulesets, keyed
        # [dependency alias or nil, ruleset name]; @resolving_rulesets
        # guards `use` cycles (a load error, spec §6.4).
        @ruleset_memo = {}
        @resolving_rulesets = []
      end

      def build
        Interscript::Node::Document.new.tap do |doc|
          @doc = doc
          doc.metadata = build_metadata
          doc.tests = build_tests
          # Maps are addressed by their file-derived name (locate() and
          # Maps.transliterate use it); registering under the system code
          # made every map whose code differs from its file name resolve
          # to an auto-created empty entry — stages[:main].call crashed.
          doc.name = if @isc_doc[:filename]
            File.basename(@isc_doc[:filename].to_s, ".isc")
          else
            @isc_doc[:systemCode]
          end
          # The legacy DSL stamps doc_name on every alias and stage; the
          # Ruby/JS compilers emit run directives and alias lookups as
          # Maps.transliterate(stage.doc_name, ...) — without it every
          # aliased-dependency run compiled to transliterate(nil).
          build_dependencies(doc)
          # Imported aliases (charset libraries) resolve NOW, at adapter
          # time: their data is a charset that must compile as a character
          # class in constraints. Left to the runtime, they degrade to
          # vacuous fragments and context-gated rules fire wrongly
          # everywhere (din-grc's word-initial γκ). Dependencies load
          # FIRST so local aliases composed from imported charsets
          # (grek_latn_any = any([grek_any, …])) resolve too.
          @imported = doc.imported_aliases
          doc.aliases = build_aliases(doc.name)
          # ISC-WF-1: declarations before stage building — `use` expansion
          # resolves against the document's rulesets and its dependencies'.
          doc.languages = build_languages
          doc.rulesets = build_rulesets(doc.name)
          build_stages(doc.name).each { |name, stage| doc.stages[name] = stage }
        end
      end

      private

      def build_metadata
        meta = Interscript::Node::MetaData.new
        @isc_doc[:metadata].each do |key, value|
          meta[key.to_sym] = value
        end
        meta
      end

      def build_tests
        return nil if @isc_doc[:tests].empty?

        tests = Interscript::Node::Tests.new
        @isc_doc[:tests].each do |t|
          tests.data << [t[:input], t[:expected]]
        end
        tests
      end

      def build_aliases(doc_name)
        @isc_doc[:aliases].each_with_object({}) do |a, h|
          # The runtime resolves aliases through AliasDef#data (see
          # Interpreter::Stage#build_item); a bare item here hands it a
          # raw Array once Any#data unrolls.
          alias_def = Interscript::Node::AliasDef.new(a[:name].to_sym, convert_item(a[:value]))
          alias_def.doc_name = doc_name
          h[a[:name].to_sym] = alias_def
        end
      end

      # ISC v1 has no import marker; aliased dependencies are reached
      # through dep_aliases, which `import` does not gate. Documents
      # load through the same dispatch the compiler uses, so chains of
      # .isc/.imp dependencies resolve recursively.
      def build_dependencies(doc)
        Array(@isc_doc[:dependencies]).each do |dep_hash|
          dep = Interscript::Node::Dependency.new
          dep.full_name = dep_hash[:target]
          dep.name = dep_hash[:alias]&.to_sym
          # Aliased dependencies are stage-run targets; unaliased ones are
          # library imports (the ISC form of `dependency "posix", import:
          # true` from the .imp corpus) — their aliases merge into scope.
          dep.import = dep.name.nil?
          dep.document = load_dependency_document(dep.full_name)
          doc.dependencies << dep
          doc.dep_aliases[dep.name] = dep if dep.name
        end
      end

      def load_dependency_document(full_name)
        path = Interscript.locate(full_name)
        if path&.end_with?(".isc")
          Interscript::Compiler.parse_isc(path)
        else
          Interscript::DSL.parse(full_name)
        end
      end

      def build_stages(doc_name)
        @isc_doc[:stages].each_with_object({}) do |stage, h|
          built = build_stage(stage)
          built.doc_name = doc_name
          h[stage[:name].to_sym] = built
        end
      end

      # ISC-WF-1 W1: build + memoize every declared ruleset, fully
      # expanded (nested `use` resolved, cycles rejected).
      def build_rulesets(doc_name)
        Array(@isc_doc[:rulesets]).each_with_object({}) do |rs, h|
          h[rs[:name].to_sym] = resolve_ruleset(nil, rs[:name], doc_name: doc_name)
        end
      end

      def build_languages
        return nil unless @isc_doc[:languages]&.any?

        Interscript::Node::LanguagesDecl.new(@isc_doc[:languages].map(&:to_sym))
      end

      def build_stage(stage_def)
        stage = Interscript::Node::Stage.new(stage_def[:name].to_sym)
        expand_items(stage_def[:body]).each { |node| stage.children << node }
        stage
      end

      # Build the Nodes for one ISC stage-item def (no `use` — that goes
      # through expand_use). Returns a list; sequence blocks contribute
      # their rules individually, parallel blocks one group.
      def build_stage_item_nodes(item)
        case item[:kind]
        when :parallel
          group = Interscript::Node::Group::Parallel.new
          item[:rules].each { |r| group.children << build_rule(r) }
          [group]
        when :sequence
          item[:rules].map { |r| build_rule(r) }
        when :bare_rule
          [build_rule(item[:rule])]
        when :run
          [build_run_rule(item)]
        when :separate
          kwargs = {}
          kwargs[:separator] = item[:separator].value if item[:separator]
          [Interscript::Node::Rule::Funcall.new(:separate, **kwargs)]
        when :string_case
          [Interscript::Node::Rule::Funcall.new(item[:op].to_sym,
            **(item[:kwargs] || {}).transform_keys(&:to_sym))]
        when :compose
          [Interscript::Node::Rule::Funcall.new(:compose)]
        when :decompose
          [Interscript::Node::Rule::Funcall.new(:decompose)]
        when :funcall
          [Interscript::Node::Rule::Funcall.new(
            item[:name].to_sym,
            **item[:kwargs].transform_keys(&:to_sym)
          )]
        else
          []
        end
      end

      # -- ISC-WF-1 W1/W2: ruleset expansion --------------------------------

      # Expand a list of ISC stage-item defs into Node children, resolving
      # `use` directives recursively. Used for both stage bodies and
      # ruleset bodies (a ruleset body is a stage body, spec §3.1).
      def expand_items(items)
        Array(items).flat_map do |item|
          if item.is_a?(Hash) && item[:kind] == :use
            expand_use(item)
          else
            build_stage_item_nodes(item)
          end
        end
      end

      # Resolve + deep-copy + merge-override one `use` site (spec §3.2, §4).
      def expand_use(item)
        rs = resolve_ruleset(item[:dependency], item[:ruleset])
        apply_overrides(deep_copy_children(rs.children), item[:overrides])
      end

      # The fully-expanded Node::Ruleset for a reference, memoized.
      # Same-map rulesets build here; dependency rulesets arrive already
      # built through the recursive adapter of the dependency document.
      def resolve_ruleset(dep_alias, name, doc_name: nil)
        key = [dep_alias&.to_sym, name.to_sym]
        return @ruleset_memo[key] if @ruleset_memo&.key?(key)
        raise cycle_error(name) if @resolving_rulesets.include?(key)

        @resolving_rulesets << key
        node =
          if dep_alias
            dep = @doc.dep_aliases[dep_alias.to_sym] ||
              raise(Interscript::MapLogicError,
                "use #{dep_alias}.#{name}: no declared dependency aliased #{dep_alias}")
            dep.document&.rulesets&.[](name.to_sym) ||
              raise(Interscript::MapLogicError,
                "use #{dep_alias}.#{name}: ruleset not found in dependency #{dep.full_name}")
          else
            rs_def = Array(@isc_doc[:rulesets]).find { |r| r[:name] == name } ||
              raise(Interscript::MapLogicError, "use #{name}: ruleset not found")
            Interscript::Node::Ruleset.new(rs_def[:name].to_sym).tap do |rs|
              rs.doc_name = doc_name
              expand_items(rs_def[:body]).each { |child| rs.children << child }
            end
          end
        @ruleset_memo[key] = node
        node
      ensure
        @resolving_rulesets.delete(key)
      end

      def cycle_error(name)
        Interscript::MapLogicError.new(
          "use cycle: ruleset #{name} revisited through #{@resolving_rulesets.map { |_, n| n }.join(" -> ")}"
        )
      end

      # Per-site deep copy: expansions must not share Group nodes (the
      # Interpreter caches compiled pass trees on them) nor be mutated by
      # another site's override merge. Rule/Item leaves are read-only at
      # execution time and may be shared.
      def deep_copy_children(children)
        children.map { |node| deep_copy_node(node) }
      end

      def deep_copy_node(node)
        case node
        when Interscript::Node::Group
          copy = node.class.new(reverse_run: node.reverse_run)
          if node.is_a?(Interscript::Node::Stage)
            copy.name = node.name
            copy.doc_name = node.doc_name
            copy.dont_reverse = node.dont_reverse
          end
          copy.children = node.children.map { |c| deep_copy_node(c) }
          copy
        else
          node.dup
        end
      end

      # ISC-WF-1 W2 merge (spec §4.2). R = the fully expanded ruleset rows
      # (document order), O = the override rows.
      #   1. A row whose from is byte-exact equal to an override from is
      #      REPLACED — removed from wherever it sits; all same-from
      #      duplicates go (the ruleset's internal last-wins winner is
      #      superseded too). From-equality is computed on the node's
      #      structural inspect — for plain strings this is exactly the
      #      byte-exact string of the corpus convention.
      #   2. Kept rows keep their order and block structure (§4.2.2 with
      #      the §3.2 pass-structure inheritance).
      #   3. The override rows land at the expansion tail: appended INTO
      #      the final parallel block when the expansion ends with one, so
      #      the child rows join that block's single longest-match pass
      #      (§4.2.5, §4.3 — replacement on the source-script pass, not
      #      post-pass re-substitution); otherwise appended as trailing
      #      rows. Unmatched overrides are simply added (§4.2.4).
      def apply_overrides(children, overrides)
        return children if overrides.nil? || overrides.empty?

        o_rules = overrides.map { |r| build_rule(r) }
        o_keys = o_rules.map { |r| from_key(r) }

        kept = children.filter_map do |node|
          case node
          when Interscript::Node::Group::Parallel
            node.children.reject! { |c| c.is_a?(Interscript::Node::Rule::Sub) && o_keys.include?(from_key(c)) }
            node
          when Interscript::Node::Rule::Sub
            o_keys.include?(from_key(node)) ? nil : node
          else
            node
          end
        end

        tail = kept.last
        if tail.is_a?(Interscript::Node::Group::Parallel)
          tail.children.push(*o_rules)
        else
          kept.push(*o_rules)
        end
        kept
      end

      def from_key(rule)
        rule.from.inspect
      end

      def build_rule(rule_def)
        from = convert_item(rule_def[:from])
        to = convert_item(rule_def[:to])
        opts = {}
        %i[before after not_before not_after].each do |k|
          next unless rule_def[:constraints]&.any? { |c| c[:kind] == k }
          constraint = rule_def[:constraints].find { |c| c[:kind] == k }
          opts[k] = convert_item(constraint[:item], :class)
        end
        # ISC-WF-1 W3: the language guard rides on the rule; inert unless
        # the interpreter selects a declared language.
        opts[:when_languages] = rule_def[:when_languages] if rule_def[:when_languages]&.any?
        Interscript::Node::Rule::Sub.new(from, to, **opts)
      end

      def build_run_rule(item)
        stage_ref = Interscript::Node::Item::Stage.new(
          item[:stage].to_sym,
          map: item[:dependency]&.to_sym
        )
        Interscript::Node::Rule::Run.new(stage_ref)
      end

      def convert_item(item, ctx = :word)
        case item
        when Items::StringValue
          Interscript::Node::Item::String.new(item.value)
        when Items::None
          Interscript::Node::Item::String.new("")
        when Items::Primitive
          convert_primitive(item)
        when Items::AliasRef
          convert_alias_ref(item, ctx)
        when Items::Capture
          Interscript::Node::Item::CaptureRef.new(item.index)
        when Items::Function
          item.name.to_sym
        when Items::Concat
          convert_concat(item)
        when Items::CaptureGroup
          Interscript::Node::Item::CaptureGroup.new(convert_item(item.inner))
        when Items::Maybe
          Interscript::Node::Item::Maybe.new(convert_item(item.inner))
        when Items::Some
          Interscript::Node::Item::Some.new(convert_item(item.inner))
        when Items::Range
          # Keep the range native: both runtimes compile Any(Range) to a
          # codepoint character class [lo-hi]. Expanding it to an Array
          # iterates Ruby String#succ (a, b, … z, aa, ab …), which never
          # reaches non-ASCII codepoints and blows up the node size.
          lo = item.lo.is_a?(Items::StringValue) ? item.lo.value : item.lo
          hi = item.hi.is_a?(Items::StringValue) ? item.hi.value : item.hi
          Interscript::Node::Item::Any.new(lo..hi)
        when Items::Set
          convert_set(item)
        else
          Interscript::Node::Item::String.new(item.to_s)
        end
      end

      def convert_primitive(item)
        # In the Ruby runtime, zero-width primitives are represented as
        # Alias nodes referencing Stdlib symbols. See Stdlib::ALIASES.
        Interscript::Node::Item::Alias.new(item.name.to_sym)
      end

      def convert_alias_ref(item, ctx = :word)
        # An alias in class context (constraint position or inside a set)
        # compiles with class semantics when it names a charset — imported
        # library sets, or local aliases composed of them. Word-position
        # aliases stay Alias nodes and resolve at runtime.
        if ctx == :class
          # Unresolvable names stay vacuous here — legacy Any(nil) parity.
          resolve_charset(item.name.to_sym) || Interscript::Node::Item::String.new("")
        else
          Interscript::Node::Item::Alias.new(item.name.to_sym, map: item.map&.to_sym)
        end
      end

      # The class-semantics node for a charset alias — imported library
      # sets (Any or charset String) or local aliases composed of them —
      # or nil. Memoized; a resolving set guards alias cycles.
      def resolve_charset(name)
        return @charset_cache[name] if @charset_cache.key?(name)
        return nil if @resolving.include?(name)

        @resolving << name
        node =
          # Stdlib alias values are regex fragments ("\d", "\b") —
          # keep them as Alias nodes so the runtimes interpolate them raw;
          # wrapping in Any escapes the backslashes ([\\d] matches a
          # literal backslash or d).
          if Interscript::Stdlib::ALIASES.key?(name)
            Interscript::Node::Item::Alias.new(name)
          elsif (imp = @imported[name])
            data = imp.data
            case data
            when Interscript::Node::Item::Any
              data
            when Interscript::Node::Item::String
              Interscript::Node::Item::Any.new(data.data)
            end
          elsif (raw = @local_raw[name])
            converted = convert_item(raw)
            converted if converted.is_a?(Interscript::Node::Item::Any) || converted.is_a?(Interscript::Node::Item::String)
          end
        @resolving.delete(name)
        @charset_cache[name] = node
      end

      def convert_concat(concat)
        parts = concat.parts.map { |p| convert_item(p) }
        return parts.first if parts.size == 1
        parts.reduce { |acc, part| acc + part }
      end

      def convert_set(set)
        Interscript::Node::Item::Any.new(
          set.chars.map do |c|
            # Entries may be primitives/alias refs (e.g. any([boundary,
            # "\u200c", "\u200d"])) — stringifying them baked an object
            # inspect into the compiled character class.
            case c
            when ::String
              Interscript::Node::Item::String.new(c)
            when Items::StringValue
              Interscript::Node::Item::String.new(c.value)
            when Items::Primitive
              convert_primitive(c)
            when Items::AliasRef
              convert_alias_ref(c, :class) ||
                begin
                  # Legacy parity: a bare alias inside any(...) compiles to the
                  # Stdlib value (Any(nil) there for imported aliases). Keeping
                  # the Alias item resolves to the imported charset *string* at
                  # build time, baking a 1000-char literal into the constraint
                  # regexp — a lookbehind that never matches.
                  name = convert_alias_ref(c).name
                  val = Interscript::Stdlib::ALIASES[name]
                  val ? Interscript::Node::Item::Any.new(val) : Interscript::Node::Item::String.new("")
                end
            else
              convert_item(c)
            end
          end
        )
      end
    end
  end
end
