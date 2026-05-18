---
name: spec-driven
description: Spec-Driven Design mandate — spec before code, lane-based requirement (trivial optional, standard if behavior change, high-stakes always).
globs: "*"
applicability:
  always: true
---

# Spec-Driven Design (SDD)

## Mandate by lane

| Lane | Spec required? | Brainstorm required? |
|---|---|---|
| Trivial | Optional (only if behavior change) | Skipped |
| Standard | Required if behavior changes | If multiple viable paths |
| High-stakes | Required, always | MANDATORY (≥3 options + ADR) |

Spec = contract between Plan and Build. Each scenario → 1 test. Each clause → 1 Stage-1 review check.

**Order:** Triage → (Align if vague/high-stakes) → (Brainstorm if mandated) → **Plan** → **Spec** → Build → Verify → Review. See `rules/common/lanes.md` + `skills/preflight/SKILL.md`.

## What a spec is

Observable behavior: inputs → outputs → error cases. NOT implementation detail.

- **Testable** — ≥1 test case per statement
- **Concrete** — real field names, status codes, exception types
- **Scenario-driven** — ≥1 happy path, ≥2 failure/edge cases

## Required sections by task type

| Task | Sections |
|---|---|
| REST endpoint | Request/response schema, scenarios (≥3), auth requirements |
| Domain logic | Preconditions, postconditions, invariants, failure exceptions |
| Messaging | Event schema, delivery guarantee, idempotency, DLQ behavior |
| DB migration | DDL changes, zero-downtime strategy, rollback DDL |
| Background job | Trigger, inputs/outputs, idempotency, failure behavior |

## Minimum format

```
## Inputs
## Outputs / Side Effects
## Contracts / Invariants
## Error Cases
```

## SDD ↔ TDD relationship

```
Spec (observable behavior)
  └── Contract Tests (from spec scenarios)
        └── Implementation (minimal code to pass)
              └── Refactor (tests stay green)
```

Each scenario → ≥1 test. Spec IS the test specification.

## Review gate

Stage 1 (spec compliance): binary outcome. Fail → Stage 2 not run.

## Related

- `rules/common/lanes.md` — when spec required
- `rules/java/testing.md` — TDD discipline
- `commands/spec.md` — spec generation
