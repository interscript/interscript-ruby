# frozen_string_literal: true

require "interscript/isc"
require "interscript"

# ISC-WF-1 semantics specs: W1 expansion, W2 merge, W3 guard selection —
# exercised through DocumentBuilder → NodeAdapter → Interpreter
# (spec docs/isc-wf-1.md §§3–5).
RSpec.describe "ISC-WF-1 semantics" do
  def build_node_doc(src, filename = "wf1.isc")
    tree = Interscript::Isc::Parser.parse(src, filename: filename)
    doc = Interscript::Isc::DocumentBuilder.build(tree, filename: filename)
    Interscript::Isc::NodeAdapter.to_interscript_node(doc)
  end

  def interpreter_for(src)
    Interscript::Interpreter.new.compile(build_node_doc(src))
  end

  describe "W1 expansion" do
    let(:src) do
      <<~ISC
        system "T:e-L:Latn:1" {
          ruleset double {
            sub "x" "1"
            parallel {
              sub "y" "2"
              sub "z" "3"
            }
          }
          stage main {
            sub "a" "A"
            use double
            sub "b" "B"
          }
        }
      ISC
    end

    it "expands the ruleset in place, in document order" do
      doc = build_node_doc(src)
      stage = doc.stages[:main]
      kinds = stage.children.map { |c| c.class.name.split("::").last }
      # textual-equivalent: as if the ruleset items were written at the
      # use position (spec §3.2).
      expect(kinds).to eq(%w[Sub Sub Parallel Sub])
      expect(stage.children[0].from.data).to eq("a")
      expect(stage.children[1].from.data).to eq("x")
      expect(stage.children[2].children.map { |c| c.from.data }).to eq(%w[y z])
      expect(stage.children[3].from.data).to eq("b")
    end

    it "keeps the ruleset out of doc.stages — it never executes alone" do
      doc = build_node_doc(src)
      expect(doc.stages.keys).to eq([:main])
      expect(doc.rulesets.keys).to eq([:double])
    end

    it "inherits the pass structure: parallel items join one pass" do
      doc = build_node_doc(src)
      group = doc.stages[:main].children[2]
      expect(group).to be_a(Interscript::Node::Group::Parallel)
    end

    it "expands recursively" do
      doc = build_node_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          ruleset inner {
            sub "1" "one"
          }
          ruleset outer {
            sub "0" "zero"
            use inner
          }
          stage main {
            use outer
          }
        }
      ISC
      children = doc.stages[:main].children
      expect(children.map { |c| c.from.data }).to eq(%w[0 1])
    end

    it "rejects use cycles at load time" do
      expect {
        build_node_doc(<<~ISC)
          system "T:e-L:Latn:1" {
            ruleset a { use b }
            ruleset b { use a }
            stage main { use a }
          }
        ISC
      }.to raise_error(Interscript::MapLogicError, /use cycle/)
    end

    it "rejects self-cycles at load time" do
      expect {
        build_node_doc(<<~ISC)
          system "T:e-L:Latn:1" {
            ruleset a { use a }
            stage main { use a }
          }
        ISC
      }.to raise_error(Interscript::MapLogicError, /use cycle/)
    end

    it "rejects references to unknown rulesets at load time" do
      expect {
        build_node_doc(%(system "T:e-L:Latn:1" {\nstage main { use nope }\n}\n))
      }.to raise_error(Interscript::MapLogicError, /not found/)
    end

    it "gives every use site its own node copies" do
      doc = build_node_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          ruleset r { parallel { sub "a" "1" } }
          stage main {
            use r
            use r
          }
        }
      ISC
      g1, g2 = doc.stages[:main].children
      expect(g1).not_to equal(g2)
      expect(g1.children.first).not_to equal(g2.children.first)
    end

    it "resolves dependency-declared rulesets through the alias" do
      fixture_dir = File.expand_path("../fixtures/wf1", __dir__)
      # Scoped to this example: locate() resolves only inside the fixture
      # directory while it runs; the memoized load path of the host
      # process is untouched (the stub replaces the method).
      allow(Interscript).to receive(:load_path).and_return([fixture_dir])
      allow(Interscript).to receive(:map_aliases).and_return({})

      doc = Interscript::Compiler.parse_isc(File.join(fixture_dir, "wf1-dependent.isc"))
      children = doc.stages[:main].children
      expect(children.map { |c| c.class.name.split("::").last }).to eq(%w[Parallel Parallel])
      # "ะ"→a, "า"→ā kept from the imported ruleset; the guarded override
      # row replaces the imported "ิ" row inside the same pass; then the
      # stage's own parallel block.
      imported = children.first.children
      expect(imported.map { |c| [c.from.data, c.to.data] }).to eq([["ะ", "a"], ["า", "ā"], ["ิ", "yy"]])
      expect(imported.last.when_languages).to eq([:tha])
    end
  end

  describe "W2 use-with-override merge" do
    # Leading parallel block, so overridden rows join the same
    # longest-match pass (spec §4.3).
    let(:src) do
      <<~ISC
        system "T:e-L:Latn:1" {
          ruleset r {
            parallel {
              sub "ะ" "a"
              sub "ั" "han"
              sub "า" "aa"
            }
          }
          stage main {
            use r override {
              sub "ะ" "q"
              sub "zzz" "unmatched"
            }
            sub "k" "K"
          }
        }
      ISC
    end

    it "replaces matching rows and keeps the rest in order" do
      group = build_node_doc(src).stages[:main].children.first
      froms = group.children.map { |c| c.from.data }
      # R_kept (ั, า) in R's order, then the override rows (child-wins on
      # exact from-equality, spec §4.2.1–2, 4).
      expect(froms).to eq(%w[ั า ะ zzz])
    end

    it "appends the override rows into the trailing parallel pass" do
      doc = build_node_doc(src)
      children = doc.stages[:main].children
      # One parallel group (with overrides in it), then the stage's own
      # trailing rule.
      expect(children.size).to eq(2)
      expect(children.first).to be_a(Interscript::Node::Group::Parallel)
      expect(children.first.children.last.to).to eq(Interscript::Node::Item::String.new("unmatched"))
      expect(children.last.from.data).to eq("k")
    end

    it "replaces ALL same-from rows, including the last-wins winner" do
      doc = build_node_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          ruleset r {
            parallel {
              sub "ะ" "a"
              sub "ะ" "a2"
              sub "า" "aa"
            }
          }
          stage main {
            use r override {
              sub "ะ" "q"
            }
          }
        }
      ISC
      group = doc.stages[:main].children.first
      expect(group.children.map { |c| [c.from.data, c.to.data] })
        .to eq([["า", "aa"], ["ะ", "q"]])
    end

    it "replaces the imported row's constraints with the override row's" do
      doc = build_node_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          ruleset r {
            parallel {
              sub "ะ" "a" not_before "x"
            }
          }
          stage main {
            use r override {
              sub "ะ" "q" before "y"
            }
          }
        }
      ISC
      rule = doc.stages[:main].children.first.children.first
      expect(rule.not_before).to be_nil
      expect(rule.before).to eq(Interscript::Node::Item::String.new("y"))
    end

    it "keeps the override row's own when guard on that row alone" do
      doc = build_node_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          languages tha
          ruleset r {
            parallel {
              sub "ิ" "i"
            }
          }
          stage main {
            use r override {
              sub "ิ" "yy" when tha
            }
          }
        }
      ISC
      rule = doc.stages[:main].children.first.children.first
      expect(rule.when_languages).to eq([:tha])
    end

    it "transliterates with the override winning over the imported row" do
      i = interpreter_for(src)
      expect(i.call("ะัาk")).to eq("qhanaaK")
    end

    it "appends trailing bare rows when the expansion does not end in a parallel block" do
      doc = build_node_doc(<<~ISC)
        system "T:e-L:Latn:1" {
          ruleset r {
            sub "a" "1"
            sub "b" "2"
          }
          stage main {
            use r override {
              sub "a" "9"
              sub "c" "3"
            }
          }
        }
      ISC
      children = doc.stages[:main].children
      expect(children.map { |c| [c.from.data, c.to.data] })
        .to eq([["b", "2"], ["a", "9"], ["c", "3"]])
    end

    it "behaves exactly like the written-out expansion without overrides" do
      expanded = interpreter_for(<<~ISC)
        system "T:e-L:Latn:1" {
          ruleset r {
            parallel {
              sub "ะ" "a"
              sub "ั" "han"
            }
          }
          stage main {
            use r
            sub "k" "K"
          }
        }
      ISC
      written = interpreter_for(<<~ISC)
        system "T:e-L:Latn:1" {
          stage main {
            parallel {
              sub "ะ" "a"
              sub "ั" "han"
            }
            sub "k" "K"
          }
        }
      ISC
      expect(expanded.call("ะัk")).to eq(written.call("ะัk"))
    end
  end

  describe "W3 language conditioning" do
    let(:iso9) do
      <<~ISC
        system "ISO:rus-Cyrl:Latn:9-1995" {
          languages kur ckv
          stage main {
            parallel {
              sub "қ" "ķ"
              sub "қ" "k̦" when kur
              sub "ҫ" "ş"
              sub "ҫ" "ș" when ckv
            }
          }
        }
      ISC
    end

    def iso9_interp
      interpreter_for(iso9)
    end

    it "renders the generic value with no language selected" do
      expect(iso9_interp.call("қҫ")).to eq("ķş")
    end

    it "applies the matching guard (kur)" do
      expect(iso9_interp.call("қҫ", language: :kur)).to eq("k̦ş")
    end

    it "applies the matching guard (ckv) and leaves others inert" do
      expect(iso9_interp.call("қҫ", language: "ckv")).to eq("ķș")
    end

    it "leaves every guard inert for a selection outside the declaration" do
      expect(iso9_interp.call("қҫ", language: :zzz)).to eq("ķş")
    end

    it "leaves every guard inert on a map without a declaration" do
      i = interpreter_for(<<~ISC)
        system "T:e-L:Latn:1" {
          stage main {
            parallel {
              sub "a" "generic"
              sub "a" "guarded" when kur
            }
          }
        }
      ISC
      expect(i.call("a")).to eq("generic")
      expect(i.call("a", language: :kur)).to eq("generic")
    end

    it "makes guard-applicable rules win over unguarded same-from rules" do
      expect(iso9_interp.call("қ", language: :kur)).to eq("k̦")
    end

    it "carries the selection through run directives" do
      i = interpreter_for(<<~ISC)
        system "T:e-L:Latn:1" {
          languages kur
          stage pre {
            parallel {
              sub "a" "generic"
              sub "a" "guarded" when kur
            }
          }
          stage main {
            run stage.pre
          }
        }
      ISC
      expect(i.call("a", language: :kur)).to eq("guarded")
      expect(i.call("a")).to eq("generic")
    end

    it "skips inert guarded rules in sequence blocks" do
      i = interpreter_for(<<~ISC)
        system "T:e-L:Latn:1" {
          languages kur
          stage main {
            sequence {
              sub "a" "b"
              sub "b" "guarded" when kur
              sub "b" "unguarded2"
            }
          }
        }
      ISC
      expect(i.call("a", language: :kur)).to eq("guarded")
      expect(i.call("a")).to eq("unguarded2")
    end

    it "memoizes filtered variants per language without cross-contamination" do
      i = iso9_interp
      expect(i.call("қ")).to eq("ķ")
      expect(i.call("қ", language: :kur)).to eq("k̦")
      expect(i.call("қ")).to eq("ķ")
      expect(i.call("қ", language: :ckv)).to eq("ķ")
    end
  end

  describe "Node layer" do
    it "carries when_languages on Sub and reports it in inspect" do
      doc = build_node_doc(%(system "T:e-L:Latn:1" {\nstage main {\nsub "a" "b" when kur, ckv\n}\n}\n))
      rule = doc.stages[:main].children.first
      expect(rule).to be_a(Interscript::Node::Rule::Sub)
      expect(rule.when_languages).to eq(%i[kur ckv])
      expect(rule.inspect).to include("when: kur, ckv")
    end

    it "excludes unguarded rules from the to_hash WF1 key" do
      rule = Interscript::Node::Rule::Sub.new("a", "b")
      expect(rule.to_hash).not_to have_key(:when_languages)
      guarded = Interscript::Node::Rule::Sub.new("a", "b", when_languages: %i[kur])
      expect(guarded.to_hash[:when_languages]).to eq(%i[kur])
    end

    it "exposes the declaration via Node::LanguagesDecl" do
      doc = build_node_doc(%(system "T:e-L:Latn:1" {\nlanguages kur ckv\nstage main { sub "a" "b" }\n}\n))
      expect(doc.languages).to be_a(Interscript::Node::LanguagesDecl)
      expect(doc.languages.include?(:kur)).to be(true)
      expect(doc.languages.include?(:rus)).to be(false)
    end

    it "keeps reversal guard-free for unguarded corpus rules" do
      rule = Interscript::Node::Rule::Sub.new("a", "b").reverse
      expect(rule.when_languages).to be_nil
    end
  end
end
