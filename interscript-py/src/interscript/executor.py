# Copyright 2026 Interscript Project. BSD-3-Clause (see LICENSE).
"""Stage/rule execution — port of interscript-ts's
`src/runtime/executor.ts` + `src/runtime/interpreter.ts`.

Two execution strategies for parallel blocks (matching Ruby):

- **tree mode** — every rule is constraint-free and literal-expandable;
  all (from, to) pairs go into one trie pass (longest match wins).
- **megaregexp mode** — any rule has before/after/not_before/not_after
  constraints or a regex-only alias; the whole block compiles to ONE
  alternation regex, first alternative (longest-first) wins at each
  position.

The whole block takes one path or the other — splitting produces
different output because a trie pass mutates the string before
constrained rules can compete.
"""

from __future__ import annotations

from collections.abc import Callable

import regex

from ._ir_types import (
    CompiledMap,
    FuncallInline,
    FuncallRule,
    ParallelRule,
    Rule,
    RunRule,
    Stage,
    SubRule,
)
from .context import ExecutionContext, MapResolver
from .errors import AsyncFunctionError, MapLogicError
from .items import (
    compile_item,
    compile_to_literal,
    expand_from_literals,
    max_length_of_item,
)
from .stdlib import (
    BUILTIN_FUNCTIONS,
    MegaregexpRule,
    compile_parallel_tree,
    parallel_megaregexp,
    parallel_replace_tree,
)

REGEX_FLAGS = regex.MULTILINE | regex.VERSION0 | regex.UNICODE

# Functions that need a mounted model (async ML inference). The model
# layer (interscript.models) registers handlers here at load time.
ASYNC_FUNCTIONS: set[str] = {"rababa", "secryst"}
_ASYNC_HANDLERS: dict[str, Callable[..., str]] = {}


def register_async_function(name: str, handler: Callable[..., str]) -> None:
    """Mount a handler for an ML funcall (called by interscript.models)."""
    ASYNC_FUNCTIONS.add(name)
    _ASYNC_HANDLERS[name] = handler


# ---------------------------------------------------------------------------
# Stage entry points
# ---------------------------------------------------------------------------


def execute_stage(
    map_: CompiledMap,
    stage_name: str,
    text: str,
    loader: MapResolver | None = None,
    language: str | None = None,
) -> str:
    """Run one stage by name; returns the transformed string.

    A missing stage is a no-op (returns the input unchanged), matching
    the TS runtime. `language` is the ISC-WF-1 W3 caller selection (§5.1).
    """
    stage = map_.stage(stage_name)
    if stage is None:
        return text
    ctx = ExecutionContext(map_, text, loader, language)
    execute_stage_rules(stage, ctx)
    return ctx.current


def execute_stage_rules(stage: Stage, ctx: ExecutionContext) -> None:
    """Apply an already-resolved stage's rules to a context."""
    for rule in stage.rules:
        execute_rule(rule, ctx)


# ---------------------------------------------------------------------------
# Rule dispatch (one executor per Rule kind)
# ---------------------------------------------------------------------------


def execute_rule(rule: Rule, ctx: ExecutionContext) -> None:
    kind = rule.kind
    if kind == "sub":
        if not _guard_active(rule, ctx):  # type: ignore[arg-type]
            return
        _execute_sub_rule(rule, ctx)  # type: ignore[arg-type]
    elif kind == "run":
        _execute_run_rule(rule, ctx)  # type: ignore[arg-type]
    elif kind == "funcall":
        _execute_funcall(rule, ctx)  # type: ignore[arg-type]
    elif kind == "parallel":
        _execute_parallel(rule, ctx)  # type: ignore[arg-type]
    elif kind == "sequential":
        for inner in rule.rules:  # type: ignore[union-attr]
            execute_rule(inner, ctx)
    else:  # pragma: no cover - exhaustive over the Rule union
        raise MapLogicError(f"unknown rule kind: {kind!r}")


# ---------------------------------------------------------------------------
# ISC-WF-1 W3 language guards
# ---------------------------------------------------------------------------


def _guard_active(rule: SubRule, ctx: ExecutionContext) -> bool:
    """A `when`-guarded sub rule applies only when the caller selected a
    language the map declares AND the rule's `when` list contains it
    (§5.1); unguarded rules always apply. Inert guards skip the rule
    entirely, in every context (bare, sequence, parallel)."""
    if rule.when is None:
        return True
    selected = ctx.effective_language
    return selected is not None and selected in rule.when


def _drop_shadowed_unguarded(rules: list[SubRule]) -> list[SubRule]:
    """§5.2 precedence: when a guard-applicable rule and an unguarded
    rule share the same from-string, the guard-applicable rule wins —
    the unguarded one is dropped so no first-alternative/insertion-order
    tie can resurrect the generic value. Structural equality of the
    `from` items is the same-from test (byte-exact for string rows)."""
    guarded_froms = {
        r.from_ for r in rules if r.when is not None and r.from_ is not None
    }
    if not guarded_froms:
        return rules
    return [
        r
        for r in rules
        if r.when is not None or r.from_ is None or r.from_ not in guarded_froms
    ]


# ---------------------------------------------------------------------------
# sub
# ---------------------------------------------------------------------------


def _execute_sub_rule(rule: SubRule, ctx: ExecutionContext) -> None:
    if rule.from_ is None:
        raise MapLogicError("sub rule missing 'from'")

    src = compile_item(rule.from_, ctx)
    # Constraints compile in CLASS context (charset aliases resolve
    # per-character — mirrors rs materialize_class / convert_class_alias).
    before = compile_item(rule.before, ctx, True).re if rule.before else ""
    after = compile_item(rule.after, ctx, True).re if rule.after else ""
    not_before = compile_item(rule.not_before, ctx, True).re if rule.not_before else ""
    not_after = compile_item(rule.not_after, ctx, True).re if rule.not_after else ""

    parts: list[str] = []
    if before:
        parts.append(f"(?<={before})")
    if not_before:
        parts.append(f"(?<!{not_before})")
    parts.append(src.re)
    if after:
        parts.append(f"(?={after})")
    if not_after:
        parts.append(f"(?!{not_after})")
    pattern = "".join(parts)

    try:
        re = regex.compile(pattern, REGEX_FLAGS)
    except regex.error as exc:
        raise MapLogicError(f"invalid pattern compiled from rule: {pattern!r}") from exc

    replacement = _build_replacement(rule.to, ctx)
    if isinstance(replacement, str):
        tmpl = replacement
        fn: Callable[[regex.Match], str] = lambda m: _resolve_template(tmpl, m)
    else:
        fn = replacement
    ctx.current = re.sub(fn, ctx.current)


def _resolve_template(template: str, m: regex.Match) -> str:
    """Resolve `$1`, `$2`, ... capture references in a replacement
    template. `$'`/`` $` ``/`$$` are NOT interpreted (literal), matching
    the TS runtime. Out-of-range references resolve to the whole match.
    """

    def repl(tmpl_match: regex.Match) -> str:
        idx = int(tmpl_match.group(1))
        try:
            group = m.group(idx)
        except IndexError:
            group = None
        return group if group is not None else m.group(0)

    return regex.sub(r"\$(\d+)", repl, template)


# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------


def _execute_run_rule(rule: RunRule, ctx: ExecutionContext) -> None:
    target_map = ctx.load_dependency(rule.doc_name) if rule.doc_name else ctx.map
    target = target_map.stage(rule.stage)
    if target is None:
        raise MapLogicError(f"stage not found: {rule.stage}")
    inner = ctx.with_map(target_map)
    execute_stage_rules(target, inner)
    ctx.current = inner.current


# ---------------------------------------------------------------------------
# funcall
# ---------------------------------------------------------------------------


def _resolve_function(ctx: ExecutionContext, name: str):
    if name in _ASYNC_HANDLERS:
        return _ASYNC_HANDLERS[name]
    return BUILTIN_FUNCTIONS.get(name)


def _execute_funcall(rule: FuncallRule, ctx: ExecutionContext) -> None:
    if rule.name in ASYNC_FUNCTIONS and rule.name not in _ASYNC_HANDLERS:
        raise AsyncFunctionError(rule.name)
    fn = _resolve_function(ctx, rule.name)
    if fn is None:
        raise MapLogicError(f"unknown function: {rule.name}")
    ctx.current = fn(ctx.current, rule.kwargs)


# ---------------------------------------------------------------------------
# parallel
# ---------------------------------------------------------------------------


def _tree_compatible(rule: SubRule, ctx: ExecutionContext) -> bool:
    return (
        rule.before is None
        and rule.after is None
        and rule.not_before is None
        and rule.not_after is None
        and expand_from_literals(rule.from_, ctx) is not None  # type: ignore[arg-type]
    )


def _execute_parallel(rule: ParallelRule, ctx: ExecutionContext) -> None:
    sub_rules: list[SubRule] = []
    trailing: list[Rule] = []
    for inner in rule.rules:
        if inner.kind == "sub" and inner.from_ is not None:  # type: ignore[union-attr]
            # Inert W3 guards (§5.1) leave the rule out of the pass; a
            # guard-applicable rule beats an unguarded same-from rule (§5.2).
            if _guard_active(inner, ctx):  # type: ignore[arg-type]
                sub_rules.append(inner)  # type: ignore[arg-type]
        else:
            trailing.append(inner)

    sub_rules = _drop_shadowed_unguarded(sub_rules)
    any_constrained = any(not _tree_compatible(r, ctx) for r in sub_rules)

    if not any_constrained:
        # Tree mode: every `from` expands to literals; rules whose `to`
        # is an inline funcall or non-literal are skipped (mirrors TS).
        flagged: list[tuple[str, str, bool]] = []  # (from_lit, to_lit, guarded)
        for r in sub_rules:
            if r.to is not None and r.to.kind == "funcall_inline":
                continue
            to_lit = compile_to_literal(r.to, ctx) if r.to is not None else ""
            if to_lit is None:
                continue
            from_alts = expand_from_literals(r.from_, ctx)  # type: ignore[arg-type]
            if from_alts is None:
                continue
            for from_lit in from_alts:
                flagged.append((from_lit, to_lit, r.when is not None))
        # §5.2 at string level: an expanded literal shared by a
        # guard-applicable rule and an unguarded rule keeps the guard.
        guarded_literals = {f for f, _t, g in flagged if g}
        trie_pairs = [
            (f, t) for f, t, g in flagged if g or f not in guarded_literals
        ]
        if trie_pairs:
            ctx.current = parallel_replace_tree(
                ctx.current, compile_parallel_tree(trie_pairs)
            )
    else:
        # Megaregexp mode: sort by max_length desc (declaration order as
        # tiebreaker), then build ONE alternation regex.
        def sort_key(pair: tuple[int, SubRule]):
            idx, r = pair
            length = (
                max_length_of_item(r.from_, ctx)  # type: ignore[arg-type]
                + (max_length_of_item(r.before, ctx) if r.before else 0)
                + (max_length_of_item(r.after, ctx) if r.after else 0)
                + (max_length_of_item(r.not_before, ctx) if r.not_before else 0)
                + (max_length_of_item(r.not_after, ctx) if r.not_after else 0)
                + (r.priority or 0)
            )
            return (-length, idx)

        mega_rules: list[MegaregexpRule] = []
        compiled: list[tuple[SubRule, str, str, str, str, str]] = []
        for _idx, r in sorted(enumerate(sub_rules), key=sort_key):
            src = compile_item(r.from_, ctx).re  # type: ignore[arg-type]
            # Constraints compile in CLASS context (charset aliases
            # resolve per-character — mirrors rs materialize_class).
            before = compile_item(r.before, ctx, True).re if r.before else ""
            after = compile_item(r.after, ctx, True).re if r.after else ""
            not_before = compile_item(r.not_before, ctx, True).re if r.not_before else ""
            not_after = compile_item(r.not_after, ctx, True).re if r.not_after else ""
            compiled.append((r, src, before, after, not_before, not_after))
        # §5.2 at pattern level: identical compiled `from` source under a
        # guard-applicable rule shadows the unguarded one.
        guarded_srcs = {c[1] for c in compiled if c[0].when is not None}
        for r, src, before, after, not_before, not_after in compiled:
            if r.when is None and src in guarded_srcs:
                continue
            pattern = (
                (f"(?<={before})" if before else "")
                + (f"(?<!{not_before})" if not_before else "")
                + src
                + (f"(?={after})" if after else "")
                + (f"(?!{not_after})" if not_after else "")
            )
            replacement = _build_replacement(r.to, ctx)
            if isinstance(replacement, str):
                tmpl = replacement

                def replace_fn(m: str, groups: list[str | None], _t: str = tmpl):
                    return _resolve_template(_t, _MegaMatch(m, groups))
            else:
                def replace_fn(m: str, groups: list[str | None], _f=replacement):
                    return _f(m)  # type: ignore[operator]
            mega_rules.append(MegaregexpRule(pattern=pattern, replace=replace_fn))

        ctx.current = parallel_megaregexp(ctx.current, mega_rules)

    # Non-sub rules execute after the parallel pass, in declaration order.
    for r in trailing:
        execute_rule(r, ctx)


class _MegaMatch:
    """Adapter so _resolve_template can read megaregexp captures, whose
    global numbering already includes the wrapping named group."""

    def __init__(self, whole: str, groups: list[str | None]) -> None:
        self._whole = whole
        self._groups = groups

    def group(self, idx: int) -> str | None:
        if idx == 0:
            return self._whole
        try:
            return self._groups[idx - 1]
        except IndexError:
            raise IndexError(f"no such group {idx}") from None


def _build_replacement(
    to: object, ctx: ExecutionContext
) -> str | Callable[[regex.Match], str]:
    """Replacement for a sub rule: the compiled literal of the `to` item,
    a callable for inline funcalls, or "" when `to` is absent."""
    if to is None:
        return ""
    if getattr(to, "kind", None) == "funcall_inline":
        assert isinstance(to, FuncallInline)
        fn = _resolve_function(ctx, to.name)
        if fn is None:
            raise MapLogicError(f"unknown inline function: {to.name}")
        return lambda m: fn(m.group(0), {})
    return compile_item(to, ctx).literal  # type: ignore[arg-type]
