# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Executor tests: synthetic compiled maps exercising every rule kind —
sub (with constraints + captures), run (dependency), funcall, parallel
(tree + megaregexp), alias resolution across dependencies."""

from __future__ import annotations

import pytest

from interscript._ir_types import (
    AliasItem,
    AnyCharClassItem,
    AnyItem,
    CaptureGroupItem,
    CaptureRefItem,
    CompiledMap,
    FuncallRule,
    GroupItem,
    ParallelRule,
    RepeatItem,
    RunRule,
    Stage,
    StringItem,
    SubRule,
)
from interscript.errors import AsyncFunctionError, MapLogicError
from interscript.executor import execute_stage


def make_map(stages, aliases=None, dependencies=(), system_code="test-map"):
    return CompiledMap(
        schema_version=1,
        system_code=system_code,
        dependencies=tuple(dependencies),
        stages=tuple(stages),
        aliases=dict(aliases or {}),
        functions={},
    )


def sub(src, dst, **kw):
    return SubRule(
        from_=StringItem(value=src) if isinstance(src, str) else src,
        to=StringItem(value=dst) if isinstance(dst, str) else dst,
        **kw,
    )


def stage(name, rules):
    return Stage(name=name, rules=tuple(rules))


class TestSubRule:
    def test_plain_substitution(self):
        m = make_map([stage("main", [sub("a", "b")])])
        assert execute_stage(m, "main", "aaa") == "bbb"

    def test_missing_stage_is_noop(self):
        m = make_map([stage("other", [sub("a", "b")])])
        assert execute_stage(m, "main", "aaa") == "aaa"

    def test_before_after_constraints(self):
        rules = [
            sub("a", "X", before=StringItem(value="c")),
            sub("a", "Y", after=StringItem(value="b")),
        ]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])])
        # megaregexp mode: 'a' preceded by 'c' -> X; 'a' followed by 'b' -> Y
        assert execute_stage(m, "main", "ca ab") == "cX Yb"

    def test_not_before_not_after(self):
        rules = [
            sub("a", "X", not_before=StringItem(value="c")),
            sub("a", "Y", not_after=StringItem(value="b")),
        ]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])])
        # 'a' not preceded by 'c' -> X; the 'a' after 'c' (not followed by
        # 'b') falls through to the second rule -> Y
        assert execute_stage(m, "main", "ca ab") == "cY Xb"

    def test_captures(self):
        rule = SubRule(
            from_=GroupItem(
                items=(CaptureGroupItem(data=StringItem(value="a")), StringItem(value="b"))
            ),
            to=GroupItem(
                items=(CaptureRefItem(id=1), CaptureRefItem(id=1)),
            ),
        )
        m = make_map([stage("main", [rule])])
        assert execute_stage(m, "main", "ab ab") == "aa aa"

    def test_capture_out_of_range_resolves_to_match(self):
        rule = SubRule(
            from_=StringItem(value="a"),
            to=CaptureRefItem(id=3),
        )
        m = make_map([stage("main", [rule])])
        assert execute_stage(m, "main", "ab") == "ab"


class TestParallel:
    def test_tree_mode_literal_pairs(self):
        rules = [sub("bc", "Z"), sub("a", "Y"), sub("ab", "X")]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])])
        # longest match wins per position, single pass
        assert execute_stage(m, "main", "abc") == "Xc"

    def test_megaregexp_mode_triggered_by_constraints(self):
        rules = [sub("a", "X", after=StringItem(value="c")), sub("a", "Y")]
        m = make_map([stage("main", [ParallelRule(rules=tuple(rules))])])
        assert execute_stage(m, "main", "ac a") == "Xc Y"

    def test_trailing_rules_run_after_parallel_pass(self):
        rules = [sub("a", "b")]
        m = make_map(
            [
                stage(
                    "main",
                    [
                        ParallelRule(rules=tuple(rules)),
                        FuncallRule(name="upcase"),
                    ],
                )
            ]
        )
        assert execute_stage(m, "main", "ba") == "BB"


class TestRunAndFuncall:
    def test_run_same_map_stage(self):
        m = make_map(
            [
                stage("main", [RunRule(stage="upper_stage")]),
                stage("upper_stage", [FuncallRule(name="upcase")]),
            ]
        )
        assert execute_stage(m, "main", "abc") == "ABC"

    def test_run_dependency_map(self):
        dep = make_map([stage("main", [sub("1", "one")])], system_code="dep-map")
        loader = type("L", (), {"load": staticmethod(lambda code: dep)})()
        m = make_map([stage("main", [RunRule(stage="main", doc_name="dep-map")])])
        assert execute_stage(m, "main", "12", loader) == "one2"

    def test_run_missing_stage_raises(self):
        m = make_map([stage("main", [RunRule(stage="nope")])])
        with pytest.raises(MapLogicError, match="stage not found"):
            execute_stage(m, "main", "x")

    def test_unknown_function_raises(self):
        m = make_map([stage("main", [FuncallRule(name="wat")])])
        with pytest.raises(MapLogicError, match="unknown function"):
            execute_stage(m, "main", "x")

    def test_async_function_without_model_raises(self):
        m = make_map([stage("main", [FuncallRule(name="secryst")])])
        with pytest.raises(AsyncFunctionError):
            execute_stage(m, "main", "x")

    def test_inline_funcall_in_to(self):
        from interscript._ir_types import FuncallInline

        rule = SubRule(
            from_=StringItem(value="a"), to=FuncallInline(name="upcase")
        )
        m = make_map([stage("main", [rule])])
        assert execute_stage(m, "main", "xa") == "xA"


class TestAliases:
    def test_alias_expansion(self):
        m = make_map(
            [stage("main", [sub(AliasItem(name="vowels"), "-")])],
            aliases={"vowels": AnyItem(of=(StringItem(value="a"), StringItem(value="e")))},
        )
        assert execute_stage(m, "main", "banana") == "b-n-n-"

    def test_alias_first_alternative_is_literal_in_to(self):
        rule = SubRule(
            from_=StringItem(value="q"),
            to=AnyItem(of=(StringItem(value="k"), StringItem(value="c"))),
        )
        m = make_map([stage("main", [rule])])
        # any-literal in `to` picks the first alternative (Ruby parity)
        assert execute_stage(m, "main", "qq") == "kk"

    def test_alias_from_dependency(self):
        dep = make_map([], aliases={"dashed": StringItem(value="--")}, system_code="dep-map")
        loader = type("L", (), {"load": staticmethod(lambda code: dep)})()
        m = make_map(
            [stage("main", [sub(AliasItem(name="dashed"), "+")])],
            dependencies=("dep-map",),
        )
        assert execute_stage(m, "main", "x--y", loader) == "x+y"

    def test_stdlib_boundary_alias(self):
        rule = SubRule(
            from_=AliasItem(name="boundary"), to=StringItem(value="|")
        )
        m = make_map([stage("main", [rule])])
        assert execute_stage(m, "main", "ab cd") == "|ab| |cd|"


class TestItemKinds:
    def test_char_class_range(self):
        rule = SubRule(
            from_=AnyCharClassItem(range=("a", "c")), to=StringItem(value="#")
        )
        m = make_map([stage("main", [rule])])
        assert execute_stage(m, "main", "abcd") == "###d"

    def test_repeat_maybe(self):
        rule = SubRule(
            from_=GroupItem(
                items=(
                    StringItem(value="a"),
                    RepeatItem(item=StringItem(value="b"), min=0, max=1),
                )
            ),
            to=StringItem(value="X"),
        )
        m = make_map([stage("main", [rule])])
        assert execute_stage(m, "main", "a ab abb") == "X X Xb"
