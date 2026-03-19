---
name: plan
description: Restate requirements, assess risks, and create step-by-step implementation plan. WAIT for user CONFIRM before touching any code.
---

# /plan -- Start Planning Phase

This command invokes the **planner** agent to create a comprehensive implementation plan before writing any code.

## What This Command Does

1. **Restate Requirements** - Clarify what needs to be built
2. **Identify Risks** - Surface potential issues and blockers
3. **Create Step Plan** - Break down implementation into phases
4. **Wait for Confirmation** - MUST receive user approval before proceeding

## When to Use

Use `/plan` when:

- Starting a new feature
- Making significant architectural changes
- Working on complex refactoring
- Multiple files/components will be affected
- Requirements are unclear or ambiguous

## Skip Conditions

Skip `/plan` only when ALL are true:

| Condition | Example |
|-----------|---------|
| Change is 5 lines or fewer | Fix null check, update constant |
| Single file affected | One config file, one typo |
| No new observable behavior | Rename, reformat, comment fix |
| No architectural impact | No new dependencies, no schema change |

## How It Works

The planner agent will:

1. **Analyze the request** and restate requirements in clear terms
2. **Break down into phases** with specific, actionable steps
3. **Identify dependencies** between components
4. **Assess risks** and potential blockers
5. **Estimate complexity** (High/Medium/Low)
6. **Present the plan** and WAIT for your explicit confirmation

## Example Usage

```
User: /plan Add order notification when payment is processed

Agent (planner):
# Implementation Plan: Order Notification on Payment Processed

## Requirements Restatement
- Publish a domain event when payment is processed for an order
- Persist notifications to PostgreSQL via R2DBC
- Expose GET /api/notifications/{userId} with pagination
- Consume payment events from Kafka reactively

## Implementation Phases

### Phase 1: Domain Events
- Create `PaymentProcessedEvent` record in domain/event/
- Create `OrderNotification` entity in notification/domain/
- Define `NotificationRepository` port (interface) in domain layer

### Phase 2: Notification Service
- Create `NotificationService` in notification/application/
- Implement reactive Kafka consumer in infrastructure layer
- Implement `R2dbcNotificationRepository` adapter
- Wire R2DBC schema migration via Flyway

### Phase 3: REST Endpoint
- Create `NotificationController` in notification/interfaces/
- Implement GET /api/notifications/{userId} returning Flux<NotificationDto>
- Add @Valid request parameter validation

### Phase 4: Integration Tests
- Testcontainers setup: PostgreSQL + Kafka
- NotificationServiceIntegrationTest using StepVerifier
- Contract test for GET endpoint with WebTestClient

## Dependencies
- Spring Kafka (reactive consumer)
- R2DBC PostgreSQL driver
- Flyway for schema migration
- Testcontainers (PostgreSQL + Kafka)

## Risks
- HIGH: Kafka consumer offset management -- ensure idempotent processing
- MEDIUM: R2DBC connection pool sizing under load
- MEDIUM: Notification backlog if consumer falls behind
- LOW: Pagination cursor design for high-volume users

## Estimated Complexity: MEDIUM

**WAITING FOR CONFIRMATION**: Proceed with this plan? (yes/no/modify)
```

## Approval Protocol

**CRITICAL**: The planner agent will **NOT** write any code until you explicitly confirm the plan with "yes" or "proceed" or similar affirmative response.

If you want changes, respond with:

- "modify: [your changes]"
- "different approach: [alternative]"
- "skip phase 2 and do phase 3 first"

## After Planning

- Run `/spec` to define behavioral contracts before writing code
- Run `/build` to start the TDD implementation cycle
- Use `/build-fix` if build errors occur during implementation
