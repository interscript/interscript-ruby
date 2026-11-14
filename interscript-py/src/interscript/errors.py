# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Error types for the Interscript Python runtime."""

from __future__ import annotations


class MapNotFoundError(KeyError):
    """A system code could not be resolved from any configured load path."""

    def __init__(self, system_code: str, *, load_paths: list[str] | None = None) -> None:
        self.system_code = system_code
        self.load_paths = load_paths or []
        hint = f" (load paths: {', '.join(self.load_paths)})" if self.load_paths else ""
        super().__init__(f"map not found: {system_code!r}{hint}")


class MapFormatError(ValueError):
    """A compiled JSON-IR map file is not a valid `interscript.maps.ir.v1` document."""


class IscParseError(MapFormatError):
    """An .isc source could not be parsed (bad token, unclosed block,
    malformed rule, ...).

    Carries the byte `position` plus 1-based `line`/`col` of the failure,
    mirroring the TypeScript `IscParseError`.
    """

    def __init__(self, message: str, position: int, line: int, col: int) -> None:
        self.position = position
        self.line = line
        self.col = col
        super().__init__(f"ISC parse error at line {line}:{col}: {message}")


class IscLoadError(MapFormatError):
    """A parsed .isc document could not be expanded/loaded (use cycle,
    unknown ruleset, a ruleset carrying non-rule items asked to join a
    pass, ...). The source parsed; its WF-1 constructs do not resolve.

    WO18 G9: expander-phase failures were routed through IscParseError,
    misreporting semantic failures under the parse class (rs/ruby raise
    their MapLogicError for the same failures).
    """

    def __init__(self, message: str, position: int, line: int, col: int) -> None:
        self.position = position
        self.line = line
        self.col = col
        super().__init__(f"ISC load error at line {line}:{col}: {message}")


class ArtifactIntegrityError(ValueError):
    """The compiled artifact failed its SHA256SUMS verification."""


class MapLogicError(ValueError):
    """A map's rules could not be executed (unknown function, bad pattern...)."""


class AsyncFunctionError(NotImplementedError):
    """A map requires an async ML funcall (rababa/secryst) that has no model mounted."""

    def __init__(self, name: str) -> None:
        self.name = name
        super().__init__(
            f"map calls ML function {name!r}; the model layer is not mounted "
            "(install interscript-py[ml] and load a model, see interscript.models)"
        )
