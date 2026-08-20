# 04 — Serializer completeness

## Current gaps in Serializer

The serializer handles most constructs but needs these additions:

### Block-form rules with Concat
DONE: Added block-form emission for Concat from/to items.

### Separate directive with separator
Verify: `separate separator "-"` serializes correctly.

### Range items
Verify: `any("a".."z")` serializes correctly.

### Maybe/Some items
Verify: `maybe(...)` and `some(...)` serialize correctly.

### Description with escaped braces
Verify: `\{` and `\}` in description text serialize correctly.

### Notes as braced blocks
DONE: Added ISC-native `notes { note "..." }` syntax.

## Specs needed
- Serializer spec for each item type
- Serializer spec for block-form vs compact-form rules
- Serializer spec for metadata with all field types
