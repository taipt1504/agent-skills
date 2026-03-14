---
name: spec
description: Generate behavioral spec from approved plan — define observable contracts before implementation. Gate between PLAN and BUILD phases.
triggers:
  - /spec
tools:
  - Read
  - Write
  - Grep
  - Glob
---

# /spec — Spec-Driven Design

Generate a behavioral specification from the approved plan. Defines observable contracts (inputs, outputs, error cases) that become the test specification for BUILD/TDD.

## Prerequisites

- `/plan` must have been run and approved (checkpoint `plan-approved` exists)
- If no plan exists: **STOP** — output: `"No approved plan found. Run /plan first."`

## Workflow

```
/spec
  │
  ├── 1. Read approved plan from session context
  │       └── STOP if no /plan was run or plan was rejected
  │
  ├── 2. Detect task type from plan signals
  │       ├── Controller, Handler, endpoint → REST Endpoint
  │       ├── UseCase, Service, Command, domain → Domain Logic
  │       ├── Kafka, RabbitMQ, event, consumer, producer → Messaging
  │       ├── Migration, Flyway, DDL, schema → Database Migration
  │       ├── Scheduler, cron, job, batch → Background Job
  │       └── Multiple signals → Mixed (generate spec per component)
  │
  ├── 3. Generate spec using type-specific template
  │       └── Fill with concrete values from plan context
  │
  ├── 4. Present spec for user approval
  │       ├── ✅ Approve  → /checkpoint create "spec-approved", signal BUILD
  │       ├── ✏️  Revise   → User provides feedback, regenerate
  │       └── ❌ Reject   → Return to /plan
  │
  └── 5. On approve: map spec scenarios to test cases
          └── Output: test case skeleton for tdd-guide
```

## Task Type Detection

| Signal in Plan | Detected Type |
|----------------|---------------|
| `*Controller.java`, `*Handler.java`, `endpoint`, `REST`, `API` | REST Endpoint |
| `*UseCase.java`, `*Service.java`, `Command`, `Query`, `domain` | Domain Logic |
| `Kafka`, `RabbitMQ`, `*Consumer.java`, `*Producer.java`, `event`, `topic`, `exchange` | Messaging |
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
```json
{
  "id": "uuid",
  "field1": "value",
  "status": "CREATED",
  "createdAt": "2024-01-01T00:00:00Z"
}
```

### Error (400 Bad Request)
```json
{
  "error": "VALIDATION_ERROR",
  "message": "field1 must not be blank",
  "fields": [{"field": "field1", "message": "must not be blank"}]
}
```

## Scenarios
| # | Scenario | Input | Expected | Status |
|---|----------|-------|----------|--------|
| 1 | Happy path — valid input | Valid request body | Resource created, event published | 201 |
| 2 | Validation error — blank field | field1 = "" | Validation error response | 400 |
| 3 | Conflict — duplicate | Existing resource ID | Conflict error | 409 |
| 4 | Unauthorized — no token | No auth header | Unauthorized error | 401 |

## Side Effects
- Event published: `ResourceCreatedEvent` to topic/exchange
- Database: new row in `resources` table

## Contracts
- Response `id` is always a valid UUID
- `createdAt` is server-side, never from client
- Idempotent on retry with same idempotency key (if applicable)
```

### Domain Logic Spec

```markdown
# Spec: [Use Case / Service Method]

## Operation
[One-sentence description of what this operation does]

## Preconditions
- [State that must be true before invocation]
- [e.g., "Order must exist and be in PENDING status"]

## Inputs
| Parameter | Type | Constraints |
|-----------|------|-------------|
| param1 | OrderId | Must reference existing order |
| param2 | Amount | Positive, ≤ order total |

## Postconditions
- [State after successful execution]
- [e.g., "Order status changed to CONFIRMED"]
- [e.g., "OrderConfirmedEvent published"]

## Invariants
- [Rules that must always hold]
- [e.g., "Order total = sum of line item amounts"]
- [e.g., "Status transitions: PENDING → CONFIRMED → SHIPPED (no skip)"]

## Error Cases
| Condition | Exception | Message |
|-----------|-----------|---------|
| Order not found | OrderNotFoundException | "Order {id} not found" |
| Invalid status transition | InvalidOrderStateException | "Cannot confirm order in {status} status" |
| Insufficient stock | InsufficientStockException | "Item {sku} has only {available} units" |

## Scenarios
| # | Scenario | Precondition | Action | Postcondition |
|---|----------|--------------|--------|---------------|
| 1 | Happy path | Order PENDING, stock available | Confirm order | Status = CONFIRMED, event published |
| 2 | Wrong status | Order SHIPPED | Confirm order | InvalidOrderStateException |
| 3 | No stock | Order PENDING, item OOS | Confirm order | InsufficientStockException |
```

### Messaging Spec

```markdown
# Spec: [Event / Message]

## Event Schema
- **Topic / Exchange**: order.events / order-exchange
- **Key / Routing Key**: order.{orderId}
- **Payload**:
```json
{
  "eventId": "uuid",
  "eventType": "ORDER_CREATED",
  "timestamp": "ISO-8601",
  "payload": {
    "orderId": "uuid",
    "customerId": "uuid",
    "totalAmount": 99.99
  }
}
```

## Delivery Guarantee
- [ ] At-least-once / [ ] Exactly-once
- Consumer group: `order-service-group`

## Idempotency
- Dedup key: `eventId`
- Strategy: Check processed_events table before handling

## Consumer Behavior
| # | Scenario | Input | Expected | Side Effect |
|---|----------|-------|----------|-------------|
| 1 | Happy path | Valid event | Process successfully | State updated |
| 2 | Duplicate event | Same eventId twice | Skip silently | No state change |
| 3 | Malformed payload | Missing required field | Send to DLT | Error logged |
| 4 | Processing failure | DB timeout | Retry 3x, then DLT | Alert on DLT |

## DLQ / DLT Behavior
- Max retries: 3
- Backoff: exponential (1s, 2s, 4s)
- DLT topic: `order.events.dlt`
- Alert: on DLT message count > 0
```

### Database Migration Spec

```markdown
# Spec: [Migration Name]

## DDL Changes
```sql
-- Phase 1: Expand (backwards compatible)
ALTER TABLE orders ADD COLUMN new_status VARCHAR(50);

-- Phase 2: Migrate data
UPDATE orders SET new_status = status WHERE new_status IS NULL;

-- Phase 3: Contract (after deployment verified)
ALTER TABLE orders DROP COLUMN old_status;
```

## Zero-Downtime Strategy
- Phase 1 (expand): Add new column, nullable — deploy new code that writes to both
- Phase 2 (migrate): Backfill existing rows
- Phase 3 (contract): Drop old column after all code uses new column

## Rollback
```sql
-- Reverse Phase 1
ALTER TABLE orders DROP COLUMN IF EXISTS new_status;
```

## Validation
- [ ] Migration runs on empty database
- [ ] Migration runs on database with existing data
- [ ] Rollback script works
- [ ] No locks > 5 seconds on production-size table
```

### Background Job Spec

```markdown
# Spec: [Job Name]

## Trigger
- Schedule: cron `0 2 * * *` (daily at 2 AM)
- OR Event-triggered: on `DailyReportRequested`

## Inputs
- Date range: previous 24 hours
- Source: orders table (status = COMPLETED)

## Outputs / Side Effects
- Generated report stored in S3 / database
- Notification sent to admin channel
- Metrics updated: `reports.generated.count`

## Idempotency
- Job ID: `daily-report-{date}`
- Strategy: Check if report for date already exists, skip if so

## Error Cases
| Condition | Behavior |
|-----------|----------|
| No data for period | Generate empty report, log warning |
| DB connection failure | Retry 3x with backoff, then alert |
| Partial failure (50% processed) | Resume from last processed ID |

## Scenarios
| # | Scenario | Input | Expected |
|---|----------|-------|----------|
| 1 | Happy path | 100 completed orders | Report generated, notification sent |
| 2 | No data | 0 orders in range | Empty report, warning logged |
| 3 | Duplicate run | Same date, report exists | Skip, log "already generated" |
| 4 | Mid-job failure | DB timeout at row 50 | Resume from row 50 on retry |
```

## Spec → Test Case Mapping

After spec approval, output a test case skeleton:

```
Spec Scenarios → Test Cases:
  Scenario 1 (happy path)     → shouldCreateOrderWhenValidInput()
  Scenario 2 (validation)     → shouldReturn400WhenFieldBlank()
  Scenario 3 (conflict)       → shouldReturn409WhenDuplicate()
  Scenario 4 (auth)           → shouldReturn401WhenNoToken()
```

This feeds directly into the BUILD phase TDD cycle.

## Approval Protocol

Present the completed spec and WAIT:

```
⏸️ SPEC REVIEW

Approve this spec? (approve / revise / reject)
- approve → /checkpoint create "spec-approved" — proceed to BUILD
- revise  → provide feedback, I'll update the spec
- reject  → return to /plan for re-planning
```

## Skip Conditions

Same as `/plan` — skip only when ALL are true:

| Condition | Example |
|-----------|---------|
| Change is ≤ 5 lines of code | Fix null check, update constant |
| Single file affected | One config file, one typo |
| No new observable behavior | Rename, reformat, comment fix |
| No architectural impact | No new dependencies, no schema change |
