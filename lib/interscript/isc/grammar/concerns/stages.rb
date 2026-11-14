# frozen_string_literal: true

require "parsanol"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Stages: ordered transformation pipelines.
        module Stages
          include Parsanol

          rule(:stage_block) do
            str("stage") >>
              (str("(") >> identifier.as(:stage_name) >> str(")") |
               whitespace >> identifier.as(:stage_name)) >> whitespace? >>
              braced(stage_item.repeat(0)).as(:stage)
          end

          # ISC-WF-1 W1: a named, reusable block of stage items. Declared at
          # map top level anywhere a stage may appear; never executes on its
          # own (only `use` expansion reaches the runtime).
          rule(:ruleset_block) do
            str("ruleset") >> whitespace >>
              identifier.as(:ruleset_name) >> whitespace? >>
              braced(stage_item.repeat(0)).as(:ruleset)
          end

          # ISC-WF-1 W1/W2: `use <ident>` (same-map ruleset) or
          # `use <alias>.<ident>` (dependency-declared ruleset), with an
          # optional override block of full replacement rows (child-wins on
          # exact from-equality).
          rule(:use_directive) do
            (str("use") >> whitespace >>
              identifier.as(:use_alias) >>
              (str(".") >> identifier.as(:qualified_name)).maybe >>
              (whitespace >> str("override") >> whitespace? >>
                braced(rule_line.repeat(0)).as(:use_overrides)).maybe
            ).as(:use)
          end

          # ISC-WF-1 W3: `when <ident> (","|ws <ident>)*` — a language guard
          # on a sub rule. Inert unless the caller selects a language the
          # map declares (spec §5.1). Identifiers are keyword-guarded so the
          # repeat stops at the next rule instead of swallowing it.
          rule(:when_guard) do
            (whitespace >> str("when") >> whitespace >>
              keyword.absent? >> identifier.as(:when_lang) >>
              ((comma | whitespace) >> (keyword.absent? >> identifier.as(:when_lang))).repeat
            ).as(:when)
          end

          rule(:stage_item) do
            whitespace? >>
              (sequence_block | parallel_block | run_rule | separate_directive |
                string_case_directive | compose_directive | rababa_directive |
                use_directive | bare_rule | comment_item) >>
              whitespace?
          end

          # Comments are consumed; stray identifiers are a parse error
          # (WO87/A4 strict-parse ruling: the corpus is 295/295 strict-clean,
          # so a typo'd map can no longer silently no-op).
          rule(:comment_item) do
            (str("#") >> (str("\n").absent? >> any).repeat).as(:comment)
          end

          # Bare rule directly in a stage body (not wrapped in sequence/parallel).
          # The original .imp allows this; treat it as a one-rule sequence.
          rule(:bare_rule) do
            rule.as(:bare_rule)
          end

          rule(:sequence_block) do
            str("sequence") >> whitespace? >>
              braced(rule_line.repeat(0)).as(:sequence)
          end

          rule(:parallel_block) do
            str("parallel") >> whitespace? >>
              braced(rule_line.repeat(0)).as(:parallel)
          end

          rule(:separate_directive) do
            str("separate").as(:separate) >>
              (whitespace >> str("separator") >> whitespace >>
                item_atom.as(:separator)).maybe
          end

          # `downcase`, `upcase`, `title_case` — string-case directives.
          # title_case takes an optional word_separator kwarg.
          rule(:string_case_directive) do
            (str("downcase") | str("upcase")).as(:case) |
              (str("title_case").as(:case) >>
                (whitespace >> kwarg_list.as(:case_kwargs)).maybe)
          end

          # `compose` / `decompose` — Unicode normalization directives.
          rule(:compose_directive) do
            str("compose").as(:compose) | str("decompose").as(:compose)
          end

          # `rababa config: "key"` — invoke the rababa diacritization service.
          # The keyword arguments are passed through to the runtime funcall.
          rule(:rababa_directive) do
            str("rababa").as(:funcall_name) >>
              (whitespace >> kwarg_list.as(:funcall_kwargs)).maybe
          end

          # `name: "value"` (`,`-separated). Used by rababa and other
          # function-call directives. Each kwarg is captured as a
          # subtree so multiple kwargs collect into a list.
          rule(:kwarg_list) do
            kwarg.as(:kwarg) >> (str(",") >> whitespace? >> kwarg.as(:kwarg)).repeat
          end

          rule(:kwarg) do
            identifier.as(:kwarg_name) >> whitespace? >>
              str(":") >> whitespace? >>
              quoted_string.as(:kwarg_value)
          end

          rule(:rule_line) do
            # ISC-WF-1 #3.2: a `use` directive is a rule-line item - items
            # inside a parallel/sequence block participate in that block's
            # single pass (mirrors rs grammar/isc.parg rule_line).
            whitespace? >> (rule | use_directive | comment_item) >> whitespace?
          end

          # A rule is either compact form (single line) or block form
          # (multi-line). Both produce the same semantic node.
          #
          # In compact form, `from` and `to` are single atoms (no concatenation).
          # This covers the 95% case (`sub "щ" "shch"`). Multi-atom matches
          # require the block form.
          rule(:rule) do
            block_rule | compact_rule
          end

          rule(:compact_rule) do
            str("sub") >> whitespace >>
              item_atom.as(:from) >> whitespace >>
              item_atom.as(:to) >>
              constraints >>
              when_guard.maybe
          end

          rule(:block_rule) do
            str("sub") >> whitespace? >>
              str("{") >> whitespace? >>
              str("from") >> whitespace >> item.as(:from) >> whitespace? >>
              str("to") >> whitespace >> item.as(:to) >>
              (whitespace >> constraint).repeat.as(:constraints) >>
              when_guard.maybe >>
              whitespace? >> str("}")
          end

          rule(:run_rule) do
            str("run") >> whitespace >>
              ((str("map.") >> identifier.as(:dep) >>
                str(".stage.") >> identifier.as(:stage)) |
               (str("stage.") >> identifier.as(:stage)).as(:run_stage_only))
          end
        end
      end
    end
  end
end
