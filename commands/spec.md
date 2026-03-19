---
name: spec
description: Generate behavioral spec from approved plan -- define observable contracts before implementation. Gate between PLAN and BUILD phases.
---

# /spec -- Define Behavioral Contracts

Generate a behavioral specification from the approved plan. Defines observable contracts (inputs, outputs, error cases) that become the test specification for the BUILD phase.

## Prerequisites

- `/plan` must have been run and approved
- If no plan exists: **STOP** -- output: `"No approved plan found. Run /plan first."`

## Workflow

```
/spec
  |
  +-- 1. Read approved plan from session context
  |       +-- STOP if no /plan was run or plan was rejected
  |
  +-- 2. Detect task type from plan signals
  |       +-- Controller, Handler, endpoint -> REST Endpoint
  |       +-- UseCase, Service, Command, domain -> Domain Logic
  |       +-- Kafka, RabbitMQ, event, consumer -> Messaging
  |       +-- Migration, Flyway, DDL, schema -> Database Migration
  |       +-- Scheduler, cron, job, batch -> Background Job
  |       +-- Multiple signals -> Mixed (generate spec per component)
  |
  +-- 3. Generate spec using type-specific template
  |       +-- Fill with concrete values from plan context
  |
  +-- 4. Present spec for user approval
  |       +-- Approve  -> proceed to BUILD
  |       +-- Revise   -> User provides feedback, regenerate
  |       +-- Reject   -> Return to /plan
  |
  +-- 5. On approve: map spec scenarios to test cases
          +-- Output: test case skeleton for BUILD/TDD
```

## Task Type Detection

| Signal in Plan | Detected Type |
|----------------|---------------|
| `*Controller.java`, `*Handler.java`, `endpoint`, `REST`, `API` | REST Endpoint |
| `*UseCase.java`, `*Service.java`, `Command`, `Query`, `domain` | Domain Logic |
| `Kafka`, `RabbitMQ`, `*Consumer.java`, `*Producer.java`, `event`, `topic` | Messaging |
| `*.sql`, `migration`, `Flyway`, `DDL`, `ALTER TABLE`, `schema` | Database Migration |
| `@Scheduled`, `cron`, `job`, `batch`, `*Job.java`, `*Task.java` | Background Job |

## Spec Templates

### REST Endpoint Spec

```markdown
# Spec: [Endpoint Name]

## Endpoint
- **Method**: POST / GET / PUT / DELETE
- **Path**: /api/v1/resource
- **Auth**: Bearer token / API key / Public

## Request
| Field | Type | Required | Validation |
|-------|------|----------|------------|
| field1 | String | Yes | Not blank, max 255 chars |
| field2 | Long | Yes | Positive |

## Response
### Success (201 Created / 200 OK)
{ "id": "uuid", "field1": "value", "status": "CREATED" }

### Error (400 Bad Request)
{ "error": "VALIDATION_ERROR", "message": "field1 must not be blank" }

## Scenarios
| # | Scenario | Input | Expected | Status |
|---|----------|-------|----------|--------|
| 1 | Happy path | Valid request body | Resource created | 201 |
| 2 | Validation error | field1 = "" | Validation error | 400 |
| 3 | Conflict | Existing resource ID | Conflict error | 409 |
| 4 | Unauthorized | No auth header | Unauthorized | 401 |

## Side Effects
- Event published: ResourceCreatedEvent
- Database: new row in resources table
```

### Domain Logic Spec

```markdown
# Spec: [Use Case / Service Method]

## Operation
[One-sentence description]

## Preconditions
- [State that must be true before invocation]

## Inputs
| Parameter | Type | Constraints |
|-----------|------|-------------|
| param1 | OrderId | Must reference existing order |

## Postconditions
- [State after successful execution]

## Invariants
- [Rules that must always hold]

## Error Cases
| Condition | Exception | Message |
|-----------|-----------|---------|
| Order not found | OrderNotFoundException | "Order {id} not found" |

## Scenarios
| # | Scenario | Precondition | Action | Postcondition |
|---|----------|--------------|--------|---------------|
| 1 | Happy path | Order PENDING | Confirm order | Status = CONFIRMED |
```

### Messaging Spec

```markdown
# Spec: [Event / Message]

## Event Schema
- **Topic / Exchange**: order.events
- **Key**: order.{orderId}
- **Payload**: { eventId, eventType, timestamp, payload }

## Delivery Guarantee
- At-least-once / Exactly-once
- Consumer group: order-service-group

## Idempotency
- Dedup key: eventId
- Strategy: Check processed_events table before handling

## Consumer Behavior
| # | Scenario | Input | Expected |
|---|----------|-------|----------|
| 1 | Happy path | Valid event | Process successfully |
| 2 | Duplicate | Same eventId | Skip silently |
| 3 | Malformed | Missing field | Send to DLT |
```

### Database Migration Spec

```markdown
# Spec: [Migration Name]

## DDL Changes
-- Phase 1: Expand (backwards compatible)
-- Phase 2: Migrate data
-- Phase 3: Contract (after deployment verified)

## Zero-Downtime Strategy
- Expand -> Migrate -> Contract

## Rollback
[Reverse DDL]

## Validation
- Migration runs on empty database
- Migration runs on database with existing data
- Rollback script works
- No locks > 5 seconds on production-size table
```

### Background Job Spec

```markdown
# Spec: [Job Name]

## Trigger
- Schedule: cron expression
- OR Event-triggered

## Inputs / Outputs
[Data sources and side effects]

## Idempotency
- Job ID format and dedup strategy

## Error Cases
| Condition | Behavior |
|-----------|----------|
| No data | Generate empty result, log warning |
| DB failure | Retry 3x with backoff, then alert |
```

## Spec to Test Case Mapping

After spec approval, output a test case skeleton:

```
Spec Scenarios -> Test Cases:
  Scenario 1 (happy path)     -> shouldCreateOrderWhenValidInput()
  Scenario 2 (validation)     -> shouldReturn400WhenFieldBlank()
  Scenario 3 (conflict)       -> shouldReturn409WhenDuplicate()
  Scenario 4 (auth)           -> shouldReturn401WhenNoToken()
```

This feeds directly into the BUILD phase TDD cycle.

## Task Decomposition

After spec approval, decompose into ordered atomic tasks:

| # | Task | Files | Test Method | Depends On |
|---|------|-------|-------------|------------|
| 1 | Create DTO record | CreateOrderRequest.java | -- | -- |
| 2 | Write repository method | OrderRepository.java | shouldFindByIdWhenExists() | 1 |
| 3 | Implement use case | CreateOrderUseCase.java | shouldCreateOrderWhenValid() | 1,2 |
| 4 | Add controller endpoint | OrderController.java | shouldReturn201WhenCreated() | 3 |

Each task is independently testable. BUILD phase processes tasks in order.

## Approval Protocol

Present the completed spec and WAIT:

```
SPEC REVIEW

Approve this spec? (approve / revise / reject)
- approve -> proceed to BUILD
- revise  -> provide feedback, I'll update the spec
- reject  -> return to /plan for re-planning
```
