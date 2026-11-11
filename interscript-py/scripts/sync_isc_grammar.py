# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Sync the vendored ISC grammar (src/interscript/grammar/grammar_source.py)
from a canonical interscript-ruby checkout:

    python scripts/sync_isc_grammar.py [path-to-interscript-ruby]

Defaults to the checkout that contains this package (the interscript-py
subtree lives inside interscript-ruby, so the canonical
lib/interscript/isc/grammar/isc.parg sits two levels up). Rewrites the
embedded source and the sha256 pin together, so the pin test
(tests/test_grammar_source.py) always describes the text that ships.

This mirrors interscript-ts's scripts/sync-isc-grammar.mjs; both vendored
copies must carry the same sha256 pin.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

DEFAULT_PARG = Path("lib/interscript/isc/grammar/isc.parg")
OUT_PATH = Path(__file__).resolve().parents[1] / "src" / "interscript" / "grammar" / "grammar_source.py"

HEADER = '''\
# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Vendored copy of the canonical ISC grammar:

    interscript-ruby lib/interscript/isc/grammar/isc.parg

The .parg file is the single semantic source of the ISC syntax; this
module embeds it verbatim (sha256 {sha}) so the Python parser compiles
the same grammar text the Ruby runtime ships. Update procedure:

    python scripts/sync_isc_grammar.py <path-to-interscript-ruby>

The sync script rewrites this file and the sha256 pin; the pin test
(tests/test_grammar_source.py) fails when the embedded text and the
recorded hash disagree, so drift is never silent.

This is the same file (same sha256 pin) that interscript-ts vendors via
its scripts/sync-isc-grammar.mjs — the two generated parsers must never
compile different grammar texts.
"""

from __future__ import annotations

# sha256 of the grammar text embedded below (pin for drift detection).
ISC_PARG_SHA256 = "{sha}"

# The grammar text itself, byte-identical to the ruby checkout copy.
ISC_PARG_SOURCE = {source}
'''


def main() -> int:
    argv = sys.argv[1:]
    if argv:
        root = Path(argv[0]).expanduser().resolve()
    else:
        # interscript-py/.. -> the interscript-ruby checkout that ships us.
        root = Path(__file__).resolve().parents[2]
    parg_path = root / DEFAULT_PARG
    try:
        src = parg_path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"sync_isc_grammar: cannot read {parg_path}: {exc}", file=sys.stderr)
        print(
            "sync_isc_grammar: pass the path to an interscript-ruby checkout as argv[1]",
            file=sys.stderr,
        )
        return 2

    sha = hashlib.sha256(src.encode("utf-8")).hexdigest()
    out = HEADER.format(sha=sha, source=json.dumps(src))
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(out, encoding="utf-8")
    print(f"sync_isc_grammar: wrote {OUT_PATH} (sha256 {sha})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
