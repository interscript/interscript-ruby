# 08 — Performance: CJK maps

## Status: Not started

6 maps take 15-38s to parse (Parslet PEG backtracking).
See TODO.rababa/05-performance-large-cjk-maps.md for details.

## Recommended approach
Pre-compile .isc to Ruby via Serializer + NodeAdapter, then
cache the compiled Node::Document for runtime use.
