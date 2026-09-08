# TODO.impl — round three: the Ruby corpus era

Round two's discovery: the Ruby gem is the last runtime not working
against the ISC corpus — its adapter drops dependencies (79 rspec
failures, root cause named), its lint gate never ran, and the
version-lockstep break that caused both ran silent for two weeks.
Status: ALL 3 ITEMS COMPLETE (2026-09-08). This register closed that era.

| # | Item | Priority |
|---|------|----------|
| 12 | [ISC dependencies in the NodeAdapter](12-isc-dependencies-adapter.md) | P1 |
| 13 | [Style debt unblock](13-ruby-style-debt.md) | P2 |
| 14 | [Lockstep drift guard](14-lockstep-drift-guard.md) | P2 |

Completing 12 unblocks PR #769 (the gallery parity spec, held open
with the root cause). Standing rules unchanged: TDD where behavior is
touched, staged sets verified, no attribution trailers.
