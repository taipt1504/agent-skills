---
name: lanes
description: Workflow lane definitions — trivial / standard / high-stakes. Routes tasks to appropriate gate depth.
globs: "*"
applicability:
  always: true
---

# Workflow Lanes

Three lanes route tasks to appropriate depth. Triage sets lane; every gate consults it.

## Trivial lane

**Criteria:** ≤5 lines, no behavior change (typo, format, rename, comment), no new deps, no public API, no persistence/migration

**Skipped:** Align, Brainstorm, Plan, Spec, Review Stage 1

**Required:** Execute (light TDD), Verify (compile + format), Review Stage 2, Commit

**Pre-flight:** light (3–5 lines, see `skills/preflight/SKILL.md`)

## Standard lane (default)

**Criteria:** Feature/bugfix/refactor, bounded scope, single component, no architectural impact, reversible

**Required:**
- Align (if unclear), Brainstorm (if multi-path), Plan, Spec
- Execute (subagent per slice if multi-slice)
- Verify (full), two-stage review, Learn

**Pre-flight:** full artifact every gate

## High-stakes lane

**Criteria:** Architecture/design change, schema/migration, security (auth/secrets/encryption), public API change, breaking change, new external dep

**Required (all mandatory):**
- Align, Brainstorm (min 3 solutions), Architect review (if available), ADR
- Plan, Spec (rigorous), Execute (subagent + worktree)
- Verify (full + security scan), two-stage review, Learn

**Pre-flight:** full artifact every gate

## User override

"treat as high-stakes" / "treat as trivial" — agent acknowledges + proceeds.

## State

Lane stored at `.claude/memory/state/current-triage.json`:

```json
{
  "lane": "standard",
  "task_description": "...",
  "timestamp": "ISO-8601",
  "reasoning": "...",
  "user_override": false
}
```

## Related

- `skills/triage/SKILL.md` — classification logic
- `rules/common/spec-driven.md` — spec requirement per lane
- `commands/triage.md` — manual override
