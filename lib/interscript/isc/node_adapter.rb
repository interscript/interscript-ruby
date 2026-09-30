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
      end

      def build
        Interscript::Node::Document.new.tap do |doc|
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

      def build_stage(stage_def)
        stage = Interscript::Node::Stage.new(stage_def[:name].to_sym)
        stage_def[:body].each do |item|
          case item[:kind]
          when :parallel
            group = Interscript::Node::Group::Parallel.new
            item[:rules].each { |r| group.children << build_rule(r) }
            stage.children << group
          when :sequence
            item[:rules].each { |r| stage.children << build_rule(r) }
          when :bare_rule
            stage.children << build_rule(item[:rule])
          when :run
            stage.children << build_run_rule(item)
          when :separate
            kwargs = {}
            kwargs[:separator] = item[:separator].value if item[:separator]
            stage.children << Interscript::Node::Rule::Funcall.new(:separate, **kwargs)
          when :string_case
            stage.children << Interscript::Node::Rule::Funcall.new(item[:op].to_sym,
              **(item[:kwargs] || {}).transform_keys(&:to_sym))
          when :compose
            stage.children << Interscript::Node::Rule::Funcall.new(:compose)
          when :decompose
            stage.children << Interscript::Node::Rule::Funcall.new(:decompose)
          when :funcall
            stage.children << Interscript::Node::Rule::Funcall.new(
              item[:name].to_sym,
              **item[:kwargs].transform_keys(&:to_sym)
            )
          end
        end
        stage
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
          if (imp = @imported[name])
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
