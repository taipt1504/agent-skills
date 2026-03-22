---
name: development-workflow
description: 5-phase development workflow with SDD mandate and TDD cycle
globs: "*"
---

# Development Workflow

## Phase Flow

```
PLAN → SPEC → BUILD (TDD) → VERIFY → REVIEW
```

**Skip conditions**: ALL must be true — change is ≤5 lines, single file, no new behavior, no arch impact. When in doubt, start with PLAN.

## Phases

| Phase | Command | Agent |
|-------|---------|-------|
| PLAN | `/plan` | `agents/planner.md` |
| SPEC | `/spec` | `agents/spec-writer.md` |
| BUILD (TDD) | `/verify` after impl | `agents/implementer.md` |
| VERIFY | `/verify` | — |
| REVIEW | `/review` | `agents/reviewer.md` |
