---
name: spec-driven-design
description: Spec-Driven Design mandate — spec before code
globs: "*"
---

# Spec-Driven Design (SDD)

## Mandate

A **spec** MUST be produced and approved before implementation. The spec defines observable behavior — what the system does, not how. No spec, no code.

**Skip conditions**: ≤5 lines, single file, no new behavior, cosmetic only.

## What a Spec Is

Concrete statement of observable behavior: inputs → outputs → error cases.

- **Testable**: every statement maps to at least one test case
- **Concrete**: real field names, status codes, exception types
- **Scenario-driven**: ≥1 happy path, ≥2 failure/edge cases

## Spec Artifacts by Task Type

| Task Type | Required Sections |
|-----------|-------------------|
| REST Endpoint | Request/response schema, scenarios (≥3), auth requirements |
| Domain Logic | Preconditions, postconditions, invariants, failure exceptions |
| Messaging | Event schema, delivery guarantee, idempotency, DLQ behavior |
| DB Migration | DDL changes, zero-downtime strategy, rollback DDL |
| Background Job | Trigger, inputs/outputs, idempotency, failure behavior |

## Minimum Format (All Types)

```
## Inputs
## Outputs / Side Effects
## Contracts / Invariants
## Error Cases
```

## SDD ↔ TDD Relationship

```
Spec (observable behavior)
  └── Contract Tests (from spec scenarios)
        └── Implementation (minimal code to pass)
              └── Refactor (improve while tests stay green)
```

Each spec scenario becomes one or more test cases. The spec IS the test specification.
