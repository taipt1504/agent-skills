---
name: summer-data
description: Summer Framework data layer — AuditService (builder, annotation, convenience methods), OutboxService (transactional outbox with scheduler or Debezium CDC, retry + backoff, circuit breaker, KafkaOutboxPublisher), kafka-consumer LSN-watermark idempotency (0.3.1+), R2DBC converters, table validators, and DDL scripts for audit_log and outbox_events.
triggers:
  natural: ["audit service", "outbox pattern", "summer audit", "debezium cdc", "kafka consumer idempotency", "outbox publisher"]
  code: ["AuditService", "OutboxService", "OutboxEventPublisher", "OutboxConsumerIdempotency", "DebeziumCdcEventDispatcher", "KafkaOutboxPublisher", "f8a.audit", "f8a.outbox", "f8a.kafka.consumer"]
requires: ["summer-core", "database-patterns"]
---

# Summer Data — Audit, Outbox & R2DBC

**Gate:** Verify summer-core is loaded and `io.f8a.summer:summer-platform` is in build.gradle before proceeding.

**Modules:** `summer-data-autoconfigure` | `summer-data-audit-autoconfigure` | `summer-data-outbox-autoconfigure` | `summer-data-r2dbc` | `summer-kafka-consumer` (0.3.1+) | `summer-kafka-consumer-autoconfigure` (0.3.1+)

**This SKILL.md tracks LATEST stable schema (0.3.2).** For older versions load the matching
overlay from [references/versions/](references/versions/).

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

## OutboxService (current — 0.3.x canon)

Transactional outbox with two publish modes — **scheduler** (poll the table) and **CDC**
(stream WAL via Debezium). Both modes share the same retry+backoff machinery, monitoring, and
cleanup.

```java
// 1. Save in your business transaction (R2DBC).
outboxService.saveEvent("ORDER_CREATED", orderId, payloadJson);

// 2. (Optional) override the built-in publisher.
@Bean
OutboxEventPublisher customPublisher() { ... }
```

### Built-in `KafkaOutboxPublisher` (0.3.1+)

Auto-wired when `KafkaTemplate` is on the classpath and `f8a.outbox.publisher.queue=kafka`
(default). Removes ~50 lines of boilerplate from each service. Disable by setting `queue` to any
non-`kafka` value (or by providing your own `OutboxEventPublisher` bean — auto-config backs off).

```yaml
f8a:
  outbox:
    enabled: true                        # default: true; false disables module entirely
    publisher:
      queue: kafka                       # selects KafkaOutboxPublisher (default)
      mode: scheduler                    # scheduler | cdc
      topic-prefix: ""                   # prepended to event topic
      scheduler:
        cron: "0/5 * * * * ?"            # poll cadence
        batch-size: 100
      cdc:                               # only when mode=cdc
        bootstrap-servers: ${KAFKA_BOOTSTRAP}    # defaults to spring.kafka.bootstrap-servers
        offset-storage-topic: debezium.outbox.offsets
        offset-storage-replication-factor: 3
        schema-history-topic: debezium.schema.history
        topic-prefix: ${SVC}             # was database-server-name pre-0.3.1
        publish-timeout: 30s             # Duration (was *-seconds long pre-0.3.1)
    retry:
      max-attempts: 5
      initial-interval: 1s
      multiplier: 2.0
      max-interval: 60s
      poll-interval: 10s                 # retry-task cadence
      batch-size: 100
    cleanup:
      cron: "0 0 0 * * ?"
      retention: 30d                     # Duration (was retention-days int pre-0.2.8)
    monitoring:
      cron: "0 0 * * * ?"
    circuit-breaker:
      failure-rate-threshold: 50
      minimum-events: 10
      wait-duration: 60s                 # Duration (was wait-duration-seconds pre-0.2.8)
      sliding-window-size: 100
```

CDC requires `wal_level=logical` on PostgreSQL and Debezium dependencies on the classpath. Only
one CDC instance per replication slot — use `scheduler` for multi-instance deployments. The CDC
storage moved JDBC → Kafka in 0.3.1, and (since 0.3.2) inherits SASL/SSL from `spring.kafka.*`.

### Schema columns (0.3.x)

`outbox_events` adds `next_retry_at TIMESTAMPTZ` (0.2.8) and `lsn BIGINT` (0.3.1):

```sql
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS lsn BIGINT;
```

`OutboxRetryTask` re-emits the same `ob.lsn` Kafka header on retry to keep consumer watermarks
consistent (CDC-mode only). Existing pre-0.3.1 events with `NULL` lsn fall back to old
epoch-nanos behaviour.

### Kafka header `ob.lsn` is binary (0.3.1+)

Header is 8-byte big-endian binary. Consumers bind `@Header Long lsn` directly via Spring
Messaging's default `byte[] → Long` converter. Pre-0.3.1 services emitted UTF-8 decimal strings
and produced wrong values under `@Header Long` — recompile against 0.3.1 to fix.

`OutboxEventPublisher.publish(event, headers)` takes `Map<String, byte[]>` (was
`Map<String, String>` pre-0.3.1). Custom publishers: drop any `.getBytes(UTF_8)` calls — values
are already bytes.

## Kafka Consumer Idempotency (0.3.1+)

`summer-kafka-consumer` introduces LSN-watermark-based dedup. Replaces per-event dedup tables
with a single row per `(consumer_group, topic, partition)` — matches Kafka's native
offset-tracking granularity, scales with topic-partition count instead of message volume.
Schema: `outbox_consumer_watermark` (see `docs/HOW_WE_IDEMPOTENCY_ON_CONSUMER.md` in Summer
docs).

```java
@KafkaListener(topics = "orders.created")
Mono<Void> onOrderCreated(OrderCreatedEvent event,
                           @Header Long lsn,
                           ConsumerRecord<?, ?> record) {
    var ctx = consumerCtx.from(record, lsn);
    return idempotency.isProcessed(ctx)
        .flatMap(seen -> seen
            ? Mono.empty()
            : process(event)
                .then(idempotency.recordProcessed(ctx)))
        .as(transactionalOperator::transactional);
}
```

Config block `f8a.kafka.consumer.{idempotency.{enabled, validate-on-startup}, retry.{max-attempts, initial-interval, multiplier, max-interval, dlt-suffix}}`.

## R2DBC Converters

Auto-configured (`SummerR2dbcAutoConfiguration`). Registers R2DBC converters for `Password` and `PhoneNumber` value objects defined in summer-core (see summer-core Shared Types).

## Version Notes

Headline only — load the matching overlay for full per-version detail:

- **0.3.2** — Debezium Kafka storage inherits SASL/SSL from `spring.kafka.*`; Swagger BOM aligned. See [versions/0.3.2.md](references/versions/0.3.2.md).
- **0.3.1** — Outbox config reshape (BREAKING): scheduler / CDC nested; Debezium storage JDBC → Kafka (BREAKING); `KafkaOutboxPublisher` auto-wired by default; outbox publish headers `Map<String, byte[]>` (BREAKING); CDC `lsn BIGINT` column preserved across retries; new `summer-kafka-consumer` module — LSN-watermark idempotency. See [versions/0.3.1.md](references/versions/0.3.1.md).
- **0.2.8** — Outbox `id` UUID → Ufid; Debezium CDC mode added; unified retry+backoff in both modes; `OutboxProperties` redesign (BREAKING — Duration types, scheduler/cleanup/monitoring grouping); `next_retry_at` column. See [versions/0.2.8.md](references/versions/0.2.8.md).
- **0.2.1** — `auditNonEntity` arg order change (BREAKING); `audit(AuditLog)` builder; `auditCustom()` deprecated; `@Audit` on Flux fix (audit once post-complete); double-subscribe fix on Mono; `AbstractTableValidator` base; embedded Flyway scripts removed (use your own); `BusinessChange` model deleted; `validate-schema` props removed (auto-detected). See [versions/0.2.1.md](references/versions/0.2.1.md).

See [references/ddl-scripts.md](references/ddl-scripts.md) for `audit_log`, `outbox_events`, and
(0.3.1+) `outbox_consumer_watermark` DDL.

For the full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Rules

- Always audit entity changes with `AuditService` — use builder pattern for complex audits, convenience methods for simple CRUD.
- Always include `intent` field in audit entries — distinguishes USER_REQUEST from SYSTEM_SYNC/SCHEDULED_JOB.
- Always configure OutboxService scheduler and circuit breaker for production — defaults may be too aggressive.
- Never skip `audit_log` DDL migration — `AuditTableValidator` will fail on startup.

## Related Skills

- **summer-core** — Shared types used in audit entries (Member for actor)
- **database-patterns** — R2DBC repository patterns, Flyway migrations
- **messaging-patterns** — OutboxService publishes to Kafka/RabbitMQ
