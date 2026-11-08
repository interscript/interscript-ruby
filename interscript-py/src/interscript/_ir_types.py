# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Typed mirror of the compiled JSON-IR format (`interscript.maps.ir.v1`).

The format is emitted by `interscript/maps` CI
(`scripts/build-json-ir-artifact.mjs`, via interscript-ts's
`src/isc/converter.ts`) and consumed identically by the TypeScript
runtime. Field names are kept EXACTLY as serialised (camelCase) so the
loader can validate against the wire shape 1:1; runtime accessors use
the snake_case names below.

Shape summary (see interscript-ts/src/types.ts for the normative doc):

    CompiledMapJson {
      schemaVersion: 1
      systemCode: str
      dependencies: [str]
      metadata?: {str: ...}          # omitted when empty
      languages?: [str]              # ISC-WF-1 W3; omitted when undeclared
      stages: [Stage]
      aliases: {name: Item}
      functions: {name: {...}}       # always {} today
    }
    Stage   = {kind: "stage", name: str, rules: [Rule]}
    Rule    = SubRule | RunRule | FuncallRule | ParallelRule | SequentialRule
    SubRule carries optional `when: [str]` (ISC-WF-1 W3 guard).
    Item    = StringItem | CaptureGroupItem | CaptureRefItem | AliasItem
            | AnyItem | AnyCharClassItem | GroupItem | RepeatItem | StageItem
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

SCHEMA_IR_V1 = "interscript.maps.ir.v1"
SCHEMA_VERSION = 1

# ---------------------------------------------------------------------------
# Items
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class StringItem:
    value: str
    kind: str = "string"


@dataclass(frozen=True)
class CaptureGroupItem:
    data: Item
    kind: str = "capture_group"


@dataclass(frozen=True)
class CaptureRefItem:
    id: int
    kind: str = "capture_ref"


@dataclass(frozen=True)
class AliasItem:
    name: str
    map: str | None = None
    kind: str = "alias"


@dataclass(frozen=True)
class AnyItem:
    of: tuple[Item, ...]
    kind: str = "any"


@dataclass(frozen=True)
class AnyCharClassItem:
    range: tuple[str, str] | None = None
    chars: tuple[str, ...] | None = None
    kind: str = "any_char_class"


@dataclass(frozen=True)
class GroupItem:
    items: tuple[Item, ...]
    kind: str = "group"


@dataclass(frozen=True)
class RepeatItem:
    item: Item
    min: int
    max: int | None
    kind: str = "repeat"


@dataclass(frozen=True)
class StageItem:
    name: str
    kind: str = "stage_ref"


Item = (
    StringItem
    | CaptureGroupItem
    | CaptureRefItem
    | AliasItem
    | AnyItem
    | AnyCharClassItem
    | GroupItem
    | RepeatItem
    | StageItem
)


@dataclass(frozen=True)
class FuncallInline:
    """Inline function used as a SubRule's `to` (e.g. `to upcase`)."""

    name: str
    kind: str = "funcall_inline"


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SubRule:
    from_: Item | None = None
    to: Item | FuncallInline | None = None
    before: Item | None = None
    after: Item | None = None
    not_before: Item | None = None
    not_after: Item | None = None
    priority: int | None = None
    when: tuple[str, ...] | None = None  # ISC-WF-1 W3 guard languages
    kind: str = "sub"


@dataclass(frozen=True)
class RunRule:
    stage: str
    doc_name: str | None = None
    kind: str = "run"


@dataclass(frozen=True)
class FuncallRule:
    name: str
    kwargs: dict[str, Any] = field(default_factory=dict)
    kind: str = "funcall"


@dataclass(frozen=True)
class ParallelRule:
    rules: tuple[Rule, ...]
    kind: str = "parallel"


@dataclass(frozen=True)
class SequentialRule:
    rules: tuple[Rule, ...]
    kind: str = "sequential"


Rule = SubRule | RunRule | FuncallRule | ParallelRule | SequentialRule


# ---------------------------------------------------------------------------
# Stage + map
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Stage:
    name: str
    rules: tuple[Rule, ...]
    kind: str = "stage"


@dataclass(frozen=True)
class FunctionDef:
    name: str


@dataclass(frozen=True)
class CompiledMap:
    schema_version: int
    system_code: str
    dependencies: tuple[str, ...]
    stages: tuple[Stage, ...]
    aliases: dict[str, Item]
    functions: dict[str, FunctionDef]
    metadata: dict[str, Any] | None = None
    languages: tuple[str, ...] | None = None  # ISC-WF-1 W3 declared languages

    def stage(self, name: str) -> Stage | None:
        for s in self.stages:
            if s.name == name:
                return s
        return None


# ---------------------------------------------------------------------------
# JSON -> dataclass decoding (strict: unknown kinds raise MapFormatError)
# ---------------------------------------------------------------------------


def item_from_json(obj: dict[str, Any]) -> Item:
    """Decode one serialised Item union member."""
    kind = obj.get("kind")
    if kind == "string":
        return StringItem(value=obj["value"])
    if kind == "capture_group":
        return CaptureGroupItem(data=item_from_json(obj["data"]))
    if kind == "capture_ref":
        return CaptureRefItem(id=int(obj["id"]))
    if kind == "alias":
        return AliasItem(name=obj["name"], map=obj.get("map"))
    if kind == "any":
        return AnyItem(of=tuple(item_from_json(c) for c in obj["of"]))
    if kind == "any_char_class":
        rng = obj.get("range")
        chars = obj.get("chars")
        return AnyCharClassItem(
            range=tuple(rng) if rng else None,
            chars=tuple(chars) if chars else None,
        )
    if kind == "group":
        return GroupItem(items=tuple(item_from_json(c) for c in obj["items"]))
    if kind == "repeat":
        return RepeatItem(
            item=item_from_json(obj["item"]),
            min=int(obj["min"]),
            max=int(obj["max"]) if obj.get("max") is not None else None,
        )
    if kind == "stage_ref":
        return StageItem(name=obj["name"])
    raise ValueError(f"unknown item kind: {kind!r}")


def rule_from_json(obj: dict[str, Any]) -> Rule:
    """Decode one serialised Rule union member."""
    kind = obj.get("kind")
    if kind == "sub":
        to_json = obj.get("to")
        if to_json is None:
            to: Item | FuncallInline | None = None
        elif to_json.get("kind") == "funcall_inline":
            to = FuncallInline(name=to_json["name"])
        else:
            to = item_from_json(to_json)
        return SubRule(
            from_=item_from_json(obj["from"]) if obj.get("from") else None,
            to=to,
            before=item_from_json(obj["before"]) if obj.get("before") else None,
            after=item_from_json(obj["after"]) if obj.get("after") else None,
            not_before=item_from_json(obj["notBefore"]) if obj.get("notBefore") else None,
            not_after=item_from_json(obj["notAfter"]) if obj.get("notAfter") else None,
            priority=int(obj["priority"]) if obj.get("priority") is not None else None,
            when=tuple(str(w) for w in obj["when"]) if obj.get("when") else None,
        )
    if kind == "run":
        return RunRule(stage=obj["stage"], doc_name=obj.get("docName"))
    if kind == "funcall":
        return FuncallRule(name=obj["name"], kwargs=dict(obj.get("kwargs") or {}))
    if kind == "parallel":
        return ParallelRule(rules=tuple(rule_from_json(r) for r in obj["rules"]))
    if kind == "sequential":
        return SequentialRule(rules=tuple(rule_from_json(r) for r in obj["rules"]))
    raise ValueError(f"unknown rule kind: {kind!r}")


def map_from_json(obj: dict[str, Any]) -> CompiledMap:
    """Decode a full `CompiledMapJson` document."""
    if obj.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"unsupported schemaVersion: {obj.get('schemaVersion')!r}")
    return CompiledMap(
        schema_version=int(obj["schemaVersion"]),
        system_code=obj["systemCode"],
        dependencies=tuple(obj.get("dependencies", ())),
        stages=tuple(
            Stage(
                name=s["name"],
                rules=tuple(rule_from_json(r) for r in s["rules"]),
            )
            for s in obj.get("stages", ())
        ),
        aliases={name: item_from_json(it) for name, it in obj.get("aliases", {}).items()},
        functions={
            name: FunctionDef(name=fd.get("name", name))
            for name, fd in obj.get("functions", {}).items()
        },
        metadata=dict(obj["metadata"]) if obj.get("metadata") else None,
        languages=tuple(str(x) for x in obj["languages"]) if obj.get("languages") else None,
    )
