# frozen_string_literal: true

require "parslet"

module Interscript
  module Isc
    module Grammar
      module Concerns
        # Stages: ordered transformation pipelines.
        module Stages
          include Parslet

          rule(:stage_block) do
            str("stage") >> whitespace >>
              identifier.as(:stage_name) >> whitespace? >>
              braced(stage_item.repeat(0)).as(:stage)
          end

          rule(:stage_item) do
            whitespace? >>
              (sequence_block | parallel_block | run_rule | separate_directive |
                string_case_directive | compose_directive | bare_rule) >>
              whitespace?
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
            str("separate").as(:separate)
          end

          # `downcase`, `upcase`, `title_case` — string-case directives.
          rule(:string_case_directive) do
            (str("downcase") | str("upcase") | str("title_case")).as(:case)
          end

          # `compose` — compose decomposed characters (NFC-ish).
          rule(:compose_directive) do
            str("compose").as(:compose)
          end

          rule(:rule_line) do
            whitespace? >> rule >> whitespace?
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
              constraints
          end

          rule(:block_rule) do
            str("sub") >> whitespace? >>
              str("{") >> whitespace? >>
              str("from") >> whitespace >> item.as(:from) >> whitespace? >>
              str("to") >> whitespace >> item.as(:to) >>
              (whitespace >> constraint).repeat.as(:constraints) >>
              whitespace? >> str("}")
          end

          rule(:run_rule) do
            str("run") >> whitespace >>
              str("map.") >> identifier.as(:dep) >>
              str(".stage.") >> identifier.as(:stage)
          end
        end
      end
    end
  end
end
