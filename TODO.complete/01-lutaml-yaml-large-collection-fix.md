# 01 — Fix lutaml-model YAML deserialization for large collections

## Problem
The YAML round-trip works for small maps (<100 rules per parallel block)
but fails for large maps. After YAML → model → hash, some `to` items have
nil values. This affects 17/20 maps in the round-trip test.

## Root Cause
lutaml-model's YAML deserialization (`from_yaml`) doesn't properly
reconstruct nested `Item` attributes when processing large collections.
The `Item` model has 9 optional attributes (type, value, name, index,
lo, hi, chars, parts, inner) — lutaml-model may not correctly set all
of them during deserialization of deeply nested structures.

## Investigation Steps
1. Check if lutaml-model v0.8.19 has a known issue with nested Serializable types in collections
2. Test with a minimal 200-item parallel block to reproduce
3. Check if the issue is in YAML parsing (Psych) or in lutaml-model's attribute mapping
4. Consider using a custom `from_yaml` override in `Model::Item` that handles the discriminator

## Potential Fixes
### Option A: Custom deserialization for Item
Override `Item.from_yaml` to manually parse the hash and construct
the correct object based on the `type` field.

### Option B: Flatten Item into Rule
Instead of a polymorphic Item class, flatten all item attributes
into Rule (from_type, from_value, from_name, etc.). Less elegant
but avoids lutaml-model's collection deserialization issues.

### Option C: Use JSON instead of YAML
lutaml-model's JSON serialization might not have the same bug.
Test if JSON round-trip works for large collections.
