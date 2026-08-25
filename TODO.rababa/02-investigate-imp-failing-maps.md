# 02 — Investigate 2 IMP-failing maps

## Priority: MEDIUM

## Current State
Two maps fail on the Ruby DSL side but parse correctly on the ISC side:
- `bgnpcgn-tuk-Cyrl-Latn-1979`
- `bgnpcgn-tuk-Cyrl-Latn-1993`

ISC captures: 1 stage, 21 tests each. Ruby DSL raises on parse.

## Investigation Needed

1. Open each `.imp` file and identify the syntax that breaks the Ruby DSL.
2. Check whether the ISC parser's extracted data matches what the .imp intends.
3. If the ISC parser is correct (likely — it parsed successfully), the Ruby DSL
   has a bug. File an issue against the Ruby DSL.

## Files to Examine
- `/Users/mulgogi/src/interscript/maps/maps/bgnpcgn-tuk-Cyrl-Latn-1979.imp`
- `/Users/mulgogi/src/interscript/maps/maps/bgnpcgn-tuk-Cyrl-Latn-1993.imp`
- `/tmp/isc-verify/bgnpcgn-tuk-Cyrl-Latn-1979.isc`
- `/tmp/isc-verify/bgnpcgn-tuk-Cyrl-Latn-1993.isc`

## Likely Root Cause
The Ruby DSL uses `instance_exec` to parse the metadata block. Tukmen (tuk) maps
may have metadata fields with characters or syntax that the DSL's metadata
parser can't handle (e.g., Turkmen-specific characters, unusual date formats,
or specific field names not in `STANDARD_STRING_KEYS`).