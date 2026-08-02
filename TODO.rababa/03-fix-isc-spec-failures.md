# 03 — Debug and fix ISC spec failures (bundler workaround)

## Priority: HIGH

## Current State
- 73 ISC specs written, 45 failing due to Ruby 3.4 + bundler incompatibility.
- The project's `spec/spec_helper.rb` requires `bundler/setup` which raises
  `DidYouMean::SPELL_CHECKERS` NameError on Ruby 3.4.8.
- ISC specs have their own `spec/interscript/isc/spec_helper.rb` that avoids
  bundler, but `rspec` loads the project `.rspec` file which points to the main
  helper.

## Workaround
Run ISC specs with:
```bash
rspec --options /dev/null --no-profile \
  --require ./spec/interscript/isc/spec_helper.rb \
  spec/interscript/isc/
```

## Remaining Issues
1. Some specs use `parser.parse(...)` but the parser returns a hash tree, not
   an object. Assert on `tree[:system][:body]` being an Array.
2. Transform specs construct Parslet trees manually — the shape may not match
   what the parser produces. Verify by parsing a minimal .isc and inspecting
   the tree.
3. The `system_code` in the parser output is a `Parslet::Slice`, not a String.
   Call `.to_s` in assertions.

## Fix Steps
1. Fix the bundler issue globally (upgrade bundler or pin Ruby version).
2. Update spec assertions to match actual parser output shapes.
3. Add a `Rakefile` target for ISC specs: `rake spec:isc`.
4. Run in CI with `--tag isc` to isolate from the main suite.