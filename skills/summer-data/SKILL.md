---
name: summer-data
description: Summer Framework data layer — AuditService (builder, annotation, convenience methods), OutboxService (transactional outbox with scheduler and circuit breaker), R2DBC converters, table validators, and DDL scripts for audit_log and outbox_events.
triggers:
  natural: ["audit service", "outbox pattern", "summer audit"]
  code: ["AuditService", "OutboxService", "f8a.audit"]
---

# Summer Data — Audit, Outbox & R2DBC

**Gate:** Verify summer-core is loaded and io.f8a.summer:summer-platform is in build.gradle before proceeding.

**Modules:** `summer-data-autoconfigure` | `summer-data-audit-autoconfigure` | `summer-data-outbox-autoconfigure`

## AuditService

Auto-activates with R2DBC. Requires `audit_log` table (see `references/ddl-scripts.md`).
`AuditTableValidator` validates schema on startup (disable: `f8a.audit.validate-on-startup=false`).

### Primary: `audit(AuditLog)` builder — auto-fills null fields from context

```java
// Minimal (actor, request info, timestamps auto-filled)
auditService.audit(AuditLog.builder()
    .action("LOGIN").intent("USER_REQUEST").build());

// With entity + before/after payloads
auditService.audit(AuditLog.builder()
    .action("UPDATE").intent("SYSTEM_SYNC")
    .entityType("ExchangeRate").entityId(pair)
    .oldValues(mapper.valueToTree(old))
    .newValues(mapper.valueToTree(updated)).build());

// Override actor (skips security context when actorId set)
auditService.audit(AuditLog.builder()
    .action("CLEANUP").intent("SCHEDULED_JOB")
    .actorId("scheduler").actorUsername("cleanup-job").build());
```

### Convenience methods

```java
auditService.auditCreate(entity, "USER_REQUEST", "Created user");
auditService.auditUpdate(oldEntity, newEntity, "USER_REQUEST", "Updated");
auditService.auditDelete(entity, "USER_REQUEST", "Deleted user");
auditService.auditNonEntity("LOGIN", "USER_REQUEST", "User logged in");
```

### Annotation-based (Mono/Flux return types only)

`@Audit` defaults:

| Field | Default |
|---|---|
| `action` | `"TRACE"` |
| `intent` | `"USER_REQUEST"` |
| `comment` | `""` |

```java
@Audit(action = "UPDATE", comment = "Updated config")
public Mono<Void> updateConfig(ConfigRequest req) { ... }

@AuditField String name;  // marks field for diff tracking in diffValues
```

### Config

```yaml
f8a:
  audit:
    validate-on-startup: true
```

## OutboxService

Transactional outbox with scheduled publishing, circuit breaker, and cleanup.

```java
// 1. Implement publisher
@Component
public class KafkaPublisher implements OutboxEventPublisher {
    public Mono<Void> publish(OutboxEvent event) { /* send to broker */ }
    public String getPublisherName() { return "kafka"; }
}

// 2. Save in business logic
outboxService.saveEvent("ORDER_CREATED", orderId, payloadJson);
```

### Config

Non-obvious keys (scheduler cron expressions use sensible defaults):

```yaml
f8a:
  outbox:
    enabled: true                        # default: true
    publisher:
      batch-size: 100                    # events per scheduler run
    scheduler:
      cleanup:
        retention-days: 30               # days to keep published events
      failed-events:
        max-retry-threshold: 5           # stop retrying after N failures
    circuit-breaker:
      failure-rate-threshold: 50         # % failures to open circuit
      wait-duration-seconds: 60          # open→half-open wait
```

## R2DBC Converters

Auto-configured (`SummerR2dbcAutoConfiguration`). Registers R2DBC converters for `Password` and `PhoneNumber` value objects defined in summer-core (see summer-core Shared Types).

## Version Notes

- **0.2.1:** `auditNonEntity` param order changed: `(intent, action, comment)` -> `(action, intent, comment)`; `auditCustom()` deprecated in favor of `audit(AuditLog)` builder; `@Audit` on Flux now audits once after completion (bug fix); `@Audit` on Mono fixed double-subscribe; `AbstractTableValidator` base class added; embedded Flyway scripts deleted; `BusinessChange` model deleted; `f8a.outbox.validate-schema` / `f8a.audit.validate-schema` removed (auto-detected)

See `references/ddl-scripts.md` for `audit_log` and `outbox_events` table DDL.

## Rules

- Always audit entity changes with `AuditService` — use builder pattern for complex audits, convenience methods for simple CRUD.
- Always include `intent` field in audit entries — distinguishes USER_REQUEST from SYSTEM_SYNC/SCHEDULED_JOB.
- Always configure OutboxService scheduler and circuit breaker for production — defaults may be too aggressive.
- Never skip `audit_log` DDL migration — `AuditTableValidator` will fail on startup.

## Related Skills

- **summer-core** — Shared types used in audit entries (Member for actor)
- **database-patterns** — R2DBC repository patterns, Flyway migrations
- **messaging-patterns** — OutboxService publishes to Kafka/RabbitMQ
