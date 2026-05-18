---
name: summer-data
description: Summer Framework data layer — AuditService (builder, annotation, convenience methods), OutboxService (transactional outbox with scheduler or Debezium CDC, retry + backoff, circuit breaker, KafkaOutboxPublisher), kafka-consumer LSN-watermark idempotency (0.3.1+), R2DBC converters, table validators, and DDL scripts for audit_log and outbox_events.
triggers:
  natural: ["audit service", "outbox pattern", "summer audit", "debezium cdc", "kafka consumer idempotency", "outbox publisher"]
  code: ["AuditService", "OutboxService", "OutboxEventPublisher", "OutboxConsumerIdempotency", "DebeziumCdcEventDispatcher", "KafkaOutboxPublisher", "f8a.audit", "f8a.outbox", "f8a.kafka.consumer"]
requires: ["summer-core", "database-patterns"]
applicability:
  always: false
  triggers:
    files_match: ["**/*AuditService*.java", "**/*OutboxService*.java", "**/*Repository*.java"]
    code_patterns: ["AuditService", "OutboxService", "io.f8a.summer.core.outbox", "f8a.audit", "f8a.outbox"]
    task_keywords: ["audit", "outbox", "summer data", "f8a.audit", "f8a.outbox"]
    related_rules:
      - rules/java/security.md
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: AuditService / OutboxService usage OR new outbox event publisher
  MEDIUM 40-79%: repository touches audit fields (created_by, updated_by)
  LOW 1-39%: caller of summer-data service
  ZERO: project lacks io.f8a.summer or summer-data not used (verify build.gradle)
---

# Summer Data — Audit, Outbox & R2DBC

**Gate:** Verify summer-core loaded and `io.f8a.summer:summer-platform` in build.gradle.

**Modules:** `summer-data-autoconfigure` | `summer-data-audit-autoconfigure` | `summer-data-outbox-autoconfigure` | `summer-data-r2dbc` | `summer-kafka-consumer` (0.3.1+) | `summer-kafka-consumer-autoconfigure` (0.3.1+)

**Tracks LATEST stable schema (0.3.5).** Older versions: load matching overlay from [references/versions/](references/versions/).

> `summer-kafka-consumer` listener wiring (idempotency, retry, DLT) now in **summer-kafka**.
> This skill covers producer-side outbox + audit + R2DBC.

## AuditService

Auto-activates with R2DBC. Requires `audit_log` table (see `references/ddl-scripts.md`). `AuditTableValidator` validates schema on startup (disable: `f8a.audit.validate-on-startup=false`).

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

Transactional outbox with two publish modes — **CDC** (stream WAL via Debezium, preferred) and **scheduler** (poll table, multi-instance fallback). Both modes share retry+backoff, monitoring, and cleanup.

> **Recommended default: `mode: cdc`.** core-ledger-ms and payment-orchestrator-ms ship CDC as production default — sub-second latency, no polling load, native ordering by PostgreSQL LSN. Summer internal default is `scheduler` (safer for first boot without WAL); set `mode: cdc` once PG prereqs in [`references/ddl-scripts.md`](references/ddl-scripts.md) are in place. Use `scheduler` only for multi-instance deployments (one CDC instance per replication slot) or without WAL access.

```java
// 1. Save in your business transaction (R2DBC).
outboxService.saveEvent("ORDER_CREATED", orderId, payloadJson);

// 2. (Optional) override the built-in publisher.
@Bean
OutboxEventPublisher customPublisher() { ... }
```

### Built-in `KafkaOutboxPublisher` (0.3.1+)

Auto-wired when `KafkaTemplate` on classpath and `f8a.outbox.publisher.queue=kafka` (default). Removes ~50 lines of boilerplate per service. Disable by setting `queue` to any non-`kafka` value (or provide own `OutboxEventPublisher` bean — auto-config backs off).

### Recommended CDC-mode config (production default — mirrors core-ledger-ms)

```yaml
f8a:
  outbox:
    enabled: true                        # default: true; false disables module entirely
    publisher:
      queue: kafka                       # selects KafkaOutboxPublisher (default)
      mode: ${OUTBOX_PUBLISHER_MODE:cdc} # cdc | scheduler — default CDC in this service
      topic-prefix: ${OUTBOX_PUBLISHER_TOPIC_PREFIX:<svc>.}   # prepended to outbound Kafka topic
                                                              # (DIFFERENT from cdc.topic-prefix below)
      cdc:
        # --- Debezium source DB connection (the connector reads PostgreSQL WAL) ---
        connector-name: <svc>-outbox-connector
        url:      ${SPRING_FLYWAY_URL}                       # jdbc:postgresql://host:5432/<db>
        username: ${SPRING_FLYWAY_USERNAME}
        password: ${SPRING_FLYWAY_PASSWORD}
        # --- WAL / replication wiring ---
        slot-name: <svc>_cdc_slot                            # Debezium replication slot (pgoutput)
        plugin-name: pgoutput                                # default; rarely changed
        table-include-list: "<schema>\\.outbox_events"       # regex; e.g. "ledger\\.outbox_events"
        # schema-include-list:                               # optional regex filter
        # --- Kafka storage for Debezium internal state (moved JDBC → Kafka in 0.3.1) ---
        offset-storage-topic:    "<svc>.outbox.offsets"
        offset-storage-partitions: 1
        offset-storage-replication-factor: 3                 # raise to ≥3 for production
        schema-history-topic:    "<svc>.schema.history"
        # --- Source-side server name (Debezium "database.server.name"; default "outbox-server") ---
        # topic-prefix: <svc>                                # optional; default is fine for most setups
        # --- Publish behavior ---
        publish-timeout: 30s
        skip-already-published: true
      scheduler:                         # retained as retry fallback even under mode=cdc
        cron: "${OUTBOX_PUBLISHER_CRON:*/5 * * * * *}"
        batch-size: 100
    retry:
      max-attempts: 5
      initial-interval: 1s
      multiplier: 2.0
      max-interval: 60s
      poll-interval: 10s                 # retry-task cadence
      batch-size: 100
    cleanup:
      cron: "0 0 3 * * ?"                # off-peak
      retention: 14d                     # Duration (was retention-days int pre-0.2.8)
    monitoring:
      cron: "0 0 * * * ?"
    circuit-breaker:
      enabled: true
      failure-rate-threshold: 50
      minimum-events: 10
      wait-duration: 60s                 # Duration (was wait-duration-seconds pre-0.2.8)
      sliding-window-size: 100
```

Reference: `core-ledger-ms/src/main/resources/application.yml` ships exactly this shape (`mode: ${OUTBOX_PUBLISHER_MODE:cdc}`, `slot-name: ledger_cdc_slot`, `table-include-list: "ledger\\.outbox_events"`). Copy as starting point for new services owning their own PostgreSQL.

### Scheduler-mode variant (multi-instance / no WAL access)

Override at deploy with `OUTBOX_PUBLISHER_MODE=scheduler` — same YAML, no other changes. `scheduler.*` block already present; CDC block becomes inert. Use when running more than one app instance per database (one CDC instance per replication slot is hard limit) or in test environments without WAL.

**`f8a.outbox.publisher.cdc.bootstrap-servers` dropped in 0.3.2** — CDC storage uses cluster at `spring.kafka.bootstrap-servers`. Configure Kafka once at `spring.kafka.*` (SASL/SSL included); Debezium inherits it since 0.3.2.

**CDC prereqs (PostgreSQL) — required before first boot with `mode: cdc`:** `wal_level=logical`, connector DB user has `REPLICATION`, publication exists for `outbox_events`, table has `REPLICA IDENTITY DEFAULT` (uses PK) or `FULL`. See [`references/ddl-scripts.md`](references/ddl-scripts.md) §"PostgreSQL prereqs for CDC mode" for exact SQL and slot-plugin recovery. One CDC instance per replication slot — fall back to `mode: scheduler` for multi-instance deployments.

**Mode override.** `mode: ${OUTBOX_PUBLISHER_MODE:cdc}` makes CDC the default, any env can downgrade to scheduler via env var. CI/local-dev without `make cdc-setup-full` sets `OUTBOX_PUBLISHER_MODE=scheduler`; production keeps default.

**`publisher.topic-prefix` ≠ `publisher.cdc.topic-prefix`.** Publisher prefix prepended to outbound Kafka topic (e.g. `ledger.` + `order.created` → `ledger.order.created`). CDC prefix is Debezium's `database.server.name` — source identifier for replication-slot offsets and schema history. Independent strings; same value is fine but they serve different purposes.

### Schema columns (0.3.x)

`outbox_events` adds `next_retry_at TIMESTAMPTZ` (0.2.8) and `lsn BIGINT` (0.3.1):

```sql
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS lsn BIGINT;
```

`OutboxRetryTask` re-emits same `ob.lsn` Kafka header on retry (CDC-mode only). Pre-0.3.1 events with `NULL` lsn fall back to epoch-nanos.

### Kafka header `ob.lsn` is binary (0.3.1+)

Header is 8-byte big-endian binary. Consumers bind `@Header Long lsn` via Spring Messaging's default `byte[] → Long` converter. Pre-0.3.1 emitted UTF-8 decimal strings → wrong values under `@Header Long` — recompile against 0.3.1 to fix.

`OutboxEventPublisher.publish(event, headers)` takes `Map<String, byte[]>` (was `Map<String, String>` pre-0.3.1). Custom publishers: drop `.getBytes(UTF_8)` calls — values already bytes.

## Kafka Consumer Idempotency (0.3.1+)

`summer-kafka-consumer` introduces LSN-watermark-based dedup. Replaces per-event dedup tables with single row per `(consumer_group, topic, partition)` — matches Kafka's offset-tracking granularity, scales with partition count. Schema: `outbox_consumer_watermark` (see `docs/HOW_WE_IDEMPOTENCY_ON_CONSUMER.md`).

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

Auto-configured (`SummerR2dbcAutoConfiguration`). Registers R2DBC converters for `Password`, `PhoneNumber`, `Ufid`, and (0.3.5+) `Txid` (see [summer-core Shared Types](../summer-core/references/summer-types.md)).

### `Txid` converters (0.3.5+) — write side is exclusive

Two converters ship; writer side gated by property:

- `TxidConverter` — `Long ↔ Txid` for **`BIGINT`** columns. Preferred for new schemas (4× smaller index entries, native int comparison).
- `TxidUuidConverter` — `UUID ↔ Txid` for **`UUID`** columns. For legacy schemas on UUID PKs.

**Reads unambiguous** — R2DBC driver yields `Long` for BIGINT and `UUID` for UUID; both `Reading` converters always registered, selected by source type.

**Writes exclusive.** `MappingR2dbcConverter` resolves writers by Java type (no SQL-type hint) — registering both leaves choice to registration order and silently writes wrong SQL type. Exactly one writer registered, selected by `SummerR2dbcProperties.txidColumnType` (`@ConfigurationProperties("summer.r2dbc")`, enum `TxidColumnType` — `UUID` or `BIGINT`):

```yaml
summer:
  r2dbc:
    txid-column-type: uuid       # default — registers TxidUuidConverter.Writing only
    # txid-column-type: bigint   # new greenfield schemas — registers TxidConverter.Writing only
```

Spring binds enum case-insensitively. Value outside `UUID` / `BIGINT` → `BindException` at context start naming the property and offending value.

**Default `uuid`** — most eWallet services standardize on UUID PKs (saga ids, account ids, hold ids, va ids). Greenfield schemas wanting BIGINT space-savings opt in by setting the property. Mixing BIGINT and UUID `Txid` columns in same app: read side OK, **write side not** — standardize one per app.

```java
@Table("transactions")
public record Transaction(
    @Id Txid txid,             // BIGINT or UUID, matches summer.r2dbc.txid-column-type
    Ufid customerId,           // UUID (canonical key)
    BigDecimal amount,
    Instant createdAt) {}
```

Source layout:
- `io.f8a.summer.data.r2dbc.config.SummerR2dbcProperties` — `@ConfigurationProperties` bean (`summer-data-r2dbc`).
- `io.f8a.summer.data.r2dbc.config.TxidColumnType` — the enum.
- `SummerR2dbcAutoConfiguration` enables via `@EnableConfigurationProperties(SummerR2dbcProperties.class)`, switches on `properties.getTxidColumnType()` to pick writer.

## Version Notes

Headline only — full detail: load matching overlay:

- **0.3.5** — R2DBC `TxidConverter` / `TxidUuidConverter` auto-registered; writer gated by `summer.r2dbc.txid-column-type` (`uuid` default). [→](references/versions/0.3.5.md)
- **0.3.2** — Debezium Kafka storage inherits SASL/SSL from `spring.kafka.*`; Swagger BOM aligned. [→](references/versions/0.3.2.md)
- **0.3.1** — Outbox config reshape (BREAKING): scheduler/CDC nested; Debezium storage JDBC→Kafka (BREAKING); `KafkaOutboxPublisher` auto-wired; headers `Map<String, byte[]>` (BREAKING); `lsn BIGINT` preserved on retry; `summer-kafka-consumer` LSN-watermark idempotency. [→](references/versions/0.3.1.md)
- **0.2.8** — Outbox `id` UUID→Ufid; CDC mode added; unified retry+backoff; `OutboxProperties` redesign (BREAKING); `next_retry_at` column. [→](references/versions/0.2.8.md)
- **0.2.1** — `auditNonEntity` arg order (BREAKING); `audit(AuditLog)` builder; `auditCustom()` deprecated; `@Audit` Flux fix; double-subscribe fix; `AbstractTableValidator`; embedded Flyway removed; `BusinessChange` deleted; `validate-schema` removed. [→](references/versions/0.2.1.md)

See [references/ddl-scripts.md](references/ddl-scripts.md) for `audit_log`, `outbox_events`, and (0.3.1+) `outbox_consumer_watermark` DDL.

For full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Rules

- Audit entity changes with `AuditService` — builder for complex audits, convenience methods for simple CRUD.
- Include `intent` in audit entries — distinguishes USER_REQUEST from SYSTEM_SYNC/SCHEDULED_JOB.
- Configure OutboxService scheduler and circuit breaker for production — defaults may be too aggressive.
- Never skip `audit_log` DDL migration — `AuditTableValidator` fails on startup.

## Related Skills

- **summer-core** — Shared types in audit entries (Member for actor)
- **database-patterns** — R2DBC repository patterns, Flyway migrations
- **messaging-patterns** — OutboxService publishes to Kafka/RabbitMQ
