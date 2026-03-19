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

**PLAN** — Run `/plan` before writing code. Search codebase for existing patterns first. Define scope, approach, acceptance criteria.

**SPEC** — Run `/spec` after plan approval. Define inputs, outputs, error cases, scenarios. Approved spec becomes the test specification. See `spec-driven.md` for artifact types.

**BUILD (TDD)** — Write tests first from spec scenarios (RED). Implement minimal code to pass (GREEN). Refactor while green (IMPROVE). Run `/verify` after implementation.

**VERIFY** — Run `/verify` after implementation. All checks must pass: compile, test, coverage, security, static analysis.

**REVIEW** — Run `/review` before requesting commit. Address all CRITICAL findings. User commits (never auto-commit).

## Research First

Before implementing anything:
1. Search existing code for similar patterns (Grep/Glob)
2. Check library docs for current API/patterns
3. Review related tests for consistency
4. Check for shared utilities to avoid duplication
