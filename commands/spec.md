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

## Spec Generation

The spec-writer agent handles spec generation with:
- Automatic task type detection (REST, Domain Logic, Messaging, DB Migration, Background Job)
- 7-step process: Read Plan → Detect Type → Read Codebase → Generate Spec → Map to Tests → Task Decomposition → Present for Approval
- Concrete templates for each task type with field names, status codes, exception types

The agent will read the codebase to ground the spec in reality — using actual class names, exception types, and field names found in the code.

See `agents/spec-writer.md` for full template details.

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
