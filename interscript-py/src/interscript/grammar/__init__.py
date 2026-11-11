# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Grammar-driven ISC parser (generated from the canonical .parg).

Modules:
- grammar_source  — the vendored .parg text, sha256-pinned
- parg_reader     — PARG lexer/parser (Parsanol::PARG subset)
- peg             — table-driven PEG interpreter + parsanol flatten
- actions         — capture tree -> IscDocument (hand-parser parity)
- isc_parser      — compiled grammar cache + the parse_isc entry

Public entry: interscript.isc.parse_isc (kept stable there).
"""
