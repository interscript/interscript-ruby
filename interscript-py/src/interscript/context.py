# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Mutable execution context — port of interscript-ts's
`src/runtime/context.ts`.

Holds the in-flight string, the active compiled map, the alias
resolution cache, and the map loader used for dependency resolution.
"""

from __future__ import annotations

from typing import Protocol

from ._ir_types import CompiledMap, Item
from .errors import MapNotFoundError


class MapResolver(Protocol):
    """Anything that can resolve a system code to a CompiledMap."""

    def load(self, system_code: str) -> CompiledMap: ...


class ExecutionContext:
    """State carried through one stage execution."""

    def __init__(
        self,
        map_: CompiledMap,
        current: str,
        loader: MapResolver | None = None,
    ) -> None:
        self.map = map_
        self.current = current
        self.loader = loader
        self._alias_cache: dict[str, Item] = {}

    def resolve_alias(self, name: str) -> Item | None:
        """Resolve an alias against the current map, then (one level)
        against the map's declared dependencies."""
        if name in self._alias_cache:
            return self._alias_cache[name]
        resolved = self.map.aliases.get(name)
        if resolved is None and self.loader is not None:
            for dep in self.map.dependencies:
                try:
                    dep_map = self.loader.load(dep)
                except MapNotFoundError:
                    continue
                dep_alias = dep_map.aliases.get(name)
                if dep_alias is not None:
                    resolved = dep_alias
                    break
        if resolved is not None:
            self._alias_cache[name] = resolved
        return resolved

    def with_map(self, map_: CompiledMap) -> ExecutionContext:
        """Spawn a context for a different map (run rule with docName);
        same loader, fresh alias cache."""
        return ExecutionContext(map_, self.current, self.loader)

    def load_dependency(self, system_code: str) -> CompiledMap:
        if self.loader is None:
            raise MapNotFoundError(
                system_code,
                load_paths=["<no loader configured for dependency resolution>"],
            )
        return self.loader.load(system_code)
