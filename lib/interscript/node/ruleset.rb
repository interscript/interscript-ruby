class Interscript::Node::Ruleset < Interscript::Node::Stage
  # ISC-WF-1 W1: a named, reusable block of stage items. Lives on
  # Node::Document#rulesets, never in #stages — a ruleset never executes
  # on its own; it only reaches the runtime through `use` expansion
  # (a macro expansion performed at adapter time).
end
