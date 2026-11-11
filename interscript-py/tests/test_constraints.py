"""Contextual (before/after-constrained) rule regression specs — the
Python mirror of interscript-ts ``test/isc/constraints.test.ts``.

Root-cause regression (WO17, 2026-11): an IMPORTED charset alias (a
dependency map's alias resolving to a plain string, e.g. unicode's
``greek``) used in a class position — a constraint (before/
not_before/after/not_after) or an ``any()`` argument — compiled as a
literal SEQUENCE of the whole charset instead of a per-character SET.
The resulting lookbehind/lookahead could never match, silently
disabling every constrained rule built on it (the golden showed the
alalc-ell-Grek-Latn-2010 medial γκ rules never firing; the five
divergent rows are γκέγκε, Λαγκαδάς, Παγκράτι, Κονγκό, Νταγκεστάν).

RS parity (interscript-rs builder.rs):
  - convert_class_alias: imported Item::Str charsets expand one entry
    per char in class context; LOCAL string aliases stay sequences;
  - convert_any_arg: alias entries class-resolve everywhere;
  - constraints materialize in class context (materialize_class);
    from/to materialize in sequence context.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from interscript.executor import execute_stage
from interscript.isc import isc_to_compiled_map, parse_isc

LIB_CODE = "py-constraint-lib"
LIB_SRC = 'system "py-constraint-lib" {\naliases {\n  vowels = "aeiou"\n  upper = "KQV"\n}\n}\n'

ROOT = Path(__file__).resolve().parents[3]
MAPS_DIR = ROOT / "maps" / "maps"
LIBS_DIR = ROOT / "maps" / "libs"


class _Resolver:
    def __init__(self, maps: dict[str, object]) -> None:
        self._maps = maps

    def load(self, system_code: str):
        return self._maps[system_code]


def _compile(sources: dict[str, str]):
    """Parse + compile a dict of .isc sources with lazy dependency
    resolution; returns (by_code, resolver)."""

    def resolve_dependency(target: str):
        return docs.get(target)

    docs: dict[str, object] = {}
    for code, src in sources.items():
        docs[code] = parse_isc(src, filename=code, resolve_dependency=resolve_dependency)
    compiled = {code: isc_to_compiled_map(doc) for code, doc in docs.items()}
    return compiled, _Resolver(compiled)


@pytest.fixture()
def corpus_available() -> None:
    if not MAPS_DIR.is_dir():
        pytest.skip("sibling maps checkout missing")


def _run(compiled, resolver, code: str, text: str) -> str:
    return execute_stage(compiled[code], "main", text, resolver)


def test_before_imported_charset_matches_single_char() -> None:
    compiled, resolver = _compile(
        {
            LIB_CODE: LIB_SRC,
            "py-constraint-class-ctx": (
                'system "py-constraint-class-ctx" {\n'
                f'dependency "{LIB_CODE}"\n'
                "stage main {\n"
                "  sub {\n"
                '    from "x"\n'
                '    to "X"\n'
                "    before any(vowels)\n"
                "  }\n"
                "}\n"
                "}\n"
            ),
        }
    )
    code = "py-constraint-class-ctx"
    # before = lookbehind: the set char must PRECEDE the match.
    assert _run(compiled, resolver, code, "ax") == "aX"
    assert _run(compiled, resolver, code, "ux") == "uX"
    # "q" is not in the set — with the sequence bug this rule could
    # NEVER fire at all; here it must fire on set membership only.
    assert _run(compiled, resolver, code, "qx") == "qx"


def test_from_imported_charset_matches_single_char() -> None:
    compiled, resolver = _compile(
        {
            LIB_CODE: LIB_SRC,
            "py-constraint-from-set": (
                'system "py-constraint-from-set" {\n'
                f'dependency "{LIB_CODE}"\n'
                "stage main {\n"
                "  sub {\n"
                "    from any(vowels)\n"
                '    to "-"\n'
                "  }\n"
                "}\n"
                "}\n"
            ),
        }
    )
    code = "py-constraint-from-set"
    # from any(charset) matches ONE set char (megaregexp path; with the
    # sequence bug the from compiled as the whole charset literal blob).
    assert _run(compiled, resolver, code, "abc") == "-bc"


def test_local_string_alias_stays_sequence_in_class_position() -> None:
    compiled, resolver = _compile(
        {
            "py-constraint-local-alias": (
                'system "py-constraint-local-alias" {\n'
                "aliases {\n"
                '  cluster = "th"\n'
                "}\n"
                "stage main {\n"
                "  sub {\n"
                '    from "s"\n'
                '    to "S"\n'
                "    before cluster\n"
                "  }\n"
                "}\n"
                "}\n"
            )
        }
    )
    code = "py-constraint-local-alias"
    # LOCAL string aliases stay SEQUENCES even in class context (rs
    # parity): before cluster = lookbehind for the literal "th".
    assert _run(compiled, resolver, code, "ths") == "thS"
    assert _run(compiled, resolver, code, "qs") == "qs"


def _build_sibling_corpus():
    if not MAPS_DIR.is_dir():
        pytest.skip("sibling maps checkout missing")

    def resolve_dependency(target: str):
        return docs.get(target)

    docs: dict[str, object] = {}
    for directory in (LIBS_DIR, MAPS_DIR):
        for path in sorted(directory.glob("*.isc")):
            docs[path.stem] = parse_isc(
                path.read_text(encoding="utf-8"),
                filename=str(path),
                resolve_dependency=resolve_dependency,
            )
    compiled = {stem: isc_to_compiled_map(doc) for stem, doc in docs.items()}
    return compiled, _Resolver(compiled)


def test_ell_medial_gamma_rows_through_the_full_path() -> None:
    """The five alalc-ell-Grek-Latn-2010 golden rows this bug silenced,
    through the in-process parse-execute path."""
    compiled, resolver = _build_sibling_corpus()
    code = "alalc-ell-Grek-Latn-2010"
    cases = {
        "γκέγκε": "gkenke",
        "Λαγκαδάς": "Lankadas",
        "Παγκράτι": "Pankrati",
        "Κονγκό": "Konnko",
        "Νταγκεστάν": "Ḏankestan",
        # word-final γκ must keep its "gk"
        "Χονγκ Κονγκ": "Chongk Kongk",
    }
    for src, expected in cases.items():
        assert _run(compiled, resolver, code, src) == expected, src
