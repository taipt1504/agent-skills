---
name: development-workflow
description: 5-phase development workflow — ALL phases are mandatory, completing a task means completing ALL phases through REVIEW
globs: "*"
---

# Development Workflow

## Phase Flow

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

**Skip conditions**: ALL must be true — change is ≤5 lines, single file, no new behavior, no arch impact. When skipping, still run VERIFY + REVIEW after BUILD.

## Phases

| Phase | Command | Agent |
|-------|---------|-------|
| PLAN | `/plan` | `agents/planner.md` |
| SPEC | `/spec` | `agents/spec-writer.md` |
| BUILD (TDD) | `/build` | `agents/implementer.md` |
| VERIFY | `/verify` | — |
| REVIEW | `/review` | `agents/reviewer.md` |

## CRITICAL: Workflow Completion Rule

**A task is NOT complete until ALL 5 phases have been executed.** Stopping after BUILD is a workflow violation.

After BUILD completes:
1. **IMMEDIATELY** run `/verify full` — do not ask, do not wait, do not skip
2. After VERIFY passes, **IMMEDIATELY** run `/review` — do not ask, do not wait, do not skip
3. Only after REVIEW produces a verdict (APPROVE or BLOCK) is the task considered complete

**Stopping after PLAN, SPEC, or BUILD without continuing to VERIFY and REVIEW is FORBIDDEN.**
