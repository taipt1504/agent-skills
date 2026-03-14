# Spec-Driven Design (SDD)

## Mandate

A **spec** MUST be produced and approved before implementation begins. The spec defines observable behavior — what the system does, not how it does it. No spec, no code.

**Skip conditions** (same as `/plan`): change is ≤5 lines, single file, no new behavior, cosmetic only.

## What a Spec Is

A concrete statement of observable behavior: inputs → outputs → error cases.

- **Testable**: every statement maps to at least one test case
- **Concrete**: real field names, real status codes, real exception types
- **Scenario-driven**: ≥1 happy path, ≥2 failure/edge cases

## What a Spec Is NOT

- Implementation description ("use a HashMap to store...")
- Requirements restatement ("the system shall...")
- UML diagrams or class hierarchies
- Design patterns selection ("apply Strategy pattern")

## Spec Artifact by Task Type

### REST Endpoint

| Section                                                            | Required      |
| ------------------------------------------------------------------ | ------------- |
| Request schema (method, path, headers, body)                       | Yes           |
| Response schema (status codes, body shape)                         | Yes           |
| Scenarios (≥3: happy path, validation error, not found / conflict) | Yes           |
| Auth/authz requirements                                            | If applicable |

### Domain Logic

| Section                                         | Required |
| ----------------------------------------------- | -------- |
| Preconditions (valid input state)               | Yes      |
| Postconditions (output state, side effects)     | Yes      |
| Invariants (what must always hold)              | Yes      |
| Failure exceptions (specific domain exceptions) | Yes      |

### Messaging (Kafka / RabbitMQ)

| Section                                           | Required |
| ------------------------------------------------- | -------- |
| Event schema (topic/exchange, key, payload shape) | Yes      |
| Delivery guarantee (at-least-once, exactly-once)  | Yes      |
| Idempotency strategy                              | Yes      |
| DLQ / DLT behavior on failure                     | Yes      |

### Database Migration

| Section                                         | Required      |
| ----------------------------------------------- | ------------- |
| DDL changes (CREATE, ALTER, DROP)               | Yes           |
| Zero-downtime strategy (expand-contract phases) | Yes           |
| Rollback DDL                                    | Yes           |
| Data backfill (if any)                          | If applicable |

### Background Job

| Section                              | Required |
| ------------------------------------ | -------- |
| Trigger (cron, event, manual)        | Yes      |
| Inputs and outputs / side effects    | Yes      |
| Idempotency strategy                 | Yes      |
| Failure behavior (retry, DLQ, alert) | Yes      |

## Minimum Format (All Types)

Every spec MUST include these four sections regardless of task type:

```
## Inputs
[What goes in — request body, command fields, event payload, trigger condition]

## Outputs / Side Effects
[What comes out — response body, state changes, events published, records created]

## Contracts / Invariants
[What must always hold — validation rules, ordering guarantees, consistency rules]

## Error Cases
[What can go wrong — each with trigger condition and expected behavior]
```

## Enforcement

1. `/spec` command is the gate — it produces the spec artifact
2. Approved spec feeds TDD test cases in BUILD phase
3. Checkpoint `spec-approved` must exist before BUILD starts (non-trivial tasks)

## SDD ↔ TDD Relationship

```
Spec (observable behavior)
  └── Contract Tests (from spec scenarios)
        └── Implementation (minimal code to pass tests)
              └── Refactor (improve while tests stay green)
```

Each spec scenario becomes one or more test cases. The spec IS the test specification.
