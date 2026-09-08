# [COMPLETE 2026-09-08 — weekly lockstep-check workflow; failure mode evidenced this round] 14 — Lockstep drift guard (P2)

## Goal
A scheduled check that fails loudly when the maps gem version outruns
the runtime's lockstep constraint — the failure mode that ran silent
from 2026-08-26 to 2026-09-08.

## Why
The gemspec derives `interscript-maps ~> X.Y.0a` from the gem's own
version. When maps shipped 2.5.0, every CI job failed at bundler with
an opaque exit 6/13 and main sat red for two weeks. A weekly probe
that resolves the gemspec against maps main turns that into a named,
actionable alert.

## Spec
- Weekly workflow on interscript-ruby: clone maps, run
  `bundle lock` against the Gemfile with the clone as the path
  dependency; failure output includes both version numbers.
- No new dependencies; a single job.

## Acceptance
- The workflow runs green on the current pair (2.5.0/2.5.0) and
  demonstrably fails when the constraint can't resolve (verified once
  by temporarily pinning back — or trusted from this round's
  evidence, stated either way).
