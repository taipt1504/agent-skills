---
name: summer-kafka
description: Summer Framework Kafka consumer module (0.3.1+) — LSN-watermark idempotency for outbox-driven consumers, default DefaultErrorHandler with exponential-backoff retry + DLT, JSON consumer factory helpers, dedicated dltKafkaTemplate. Use when wiring @KafkaListener handlers that consume Summer outbox events (ob.lsn header) and need at-least-once-with-skip semantics without per-event dedup tables.
triggers:
  natural: ["kafka consumer idempotency", "outbox consumer", "lsn watermark", "summer kafka", "kafka dlt", "kafka retry summer"]
  code: ["OutboxConsumerIdempotency", "IdempotencyContext", "SummerKafkaConsumerFactories", "DefaultErrorHandlerCustomizer", "ConsumerWatermarkValidator", "f8a.kafka.consumer", "outbox_consumer_watermark"]
requires: ["summer-core", "summer-data"]
applicability:
  always: false
  triggers:
    files_match: ["**/*KafkaListener*.java", "**/*MessageHandler*.java", "**/*OutboxPublisher*.java"]
    code_patterns: ["io.f8a.summer.kafka", "AbstractKafkaMessageHandler", "MessageHandlerRegistry", "OutboxEventPublisher"]
    task_keywords: ["summer Kafka", "outbox dispatcher", "message handler registry", "f8a.kafka"]
    related_skills: ["messaging-patterns", "summer-data"]
    related_rules:
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: new Summer Kafka consumer/producer OR outbox routing change
  MEDIUM 40-79%: handler registry registration tweak
  LOW 1-39%: caller publishes via Summer outbox but handler in other service
  ZERO: project lacks io.f8a.summer:summer-kafka
---

# Summer Kafka — Consumer Idempotency & Error Handling

**Gate:** Verify summer-core loaded + `io.f8a.summer:summer-platform` in build.gradle. Producers must be on `summer-data-outbox` 0.3.1+ — messages must carry `ob.lsn` header.

**Modules:** `summer-kafka-consumer` | `summer-kafka-consumer-autoconfigure` (both added 0.3.1)
**Package:** `io.f8a.summer.kafka.consumer.*`
**Activation:** Auto when `summer-kafka-consumer-autoconfigure` is on the classpath. **There is no `enabled` flag — presence of the dependency is the opt-in.** Disable by dropping the dependency.

**Tracks LATEST stable (0.3.5).** First shipped 0.3.1; no 0.3.5 overlay (no kafka-consumer changes since 0.3.1).

## Why it exists

Pre-0.3.1: every consumer needed its own dedup table (one row per event) or a domain-unique key + `DuplicateKeyException`. Both scale with **message volume** and produce hot indexes. `OutboxConsumerIdempotency` watermarks by `(consumer_group, topic, partition)` — matching Kafka's native offset granularity — so storage cost is O(groups × topics × partitions), typically a few hundred rows per service regardless of throughput.

Debezium preserves PostgreSQL LSN order **within** a topic-partition. Scheduler-mode publishers emit `createdAt.toEpochNanos()` as best-effort — stable under normal load, not authoritative under extreme concurrency. Strict ordering → use CDC mode.

## Schema — `outbox_consumer_watermark`

One row per `(group, topic, partition)`. Schema must exist before consumers run; `ConsumerWatermarkValidator` checks on startup (disable: `f8a.kafka.consumer.idempotency.validate-on-startup=false`).

```sql
CREATE TABLE outbox_consumer_watermark (
    consumer_group  VARCHAR(255) NOT NULL,
    topic           VARCHAR(255) NOT NULL,
    partition       INTEGER      NOT NULL,
    last_lsn        BIGINT       NOT NULL,
    last_event_id   UUID,
    last_updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (consumer_group, topic, partition)
);
```

**Column names load-bearing** — `ConsumerWatermarkValidator` checks exact names: `consumer_group`, `topic`, `partition`, `last_lsn`, `last_event_id`, `last_updated_at`. Using `lsn`/`updated_at` instead fails boot. DDL also in `summer-data/references/ddl-scripts.md`.

## Public API

| Type | Purpose |
|---|---|
| `OutboxConsumerIdempotency` (interface) | `isProcessed(ctx) → Mono<Boolean>`, `recordProcessed(ctx) → Mono<Void>`. Both must run **in the same transaction as the business write**. |
| `R2dbcOutboxConsumerIdempotency` | Default R2DBC implementation. Auto-registered when `summer-data-r2dbc` is on the classpath. |
| `IdempotencyContext` (record) | `(consumerGroup, topic, partition, lsn, eventId)` — extracted from the inbound record's `KafkaHeaders.RECEIVED_TOPIC`, `RECEIVED_PARTITION`, and `ob.lsn` / `ob.eid` headers. |
| `ConsumerWatermarkValidator` | Startup schema validator. |
| `SummerKafkaConsumerFactories` | Static helpers: `jsonConsumerFactory(props, valueType)` and `jsonListenerContainerFactory(props, cf, errorHandler)`. |
| `DefaultErrorHandlerCustomizer` | Functional interface — add non-retryable exceptions without replacing the whole handler. |
| `dltKafkaTemplate` bean | `KafkaTemplate` configured `enable.idempotence=false, acks=1`. DLT is fire-and-forget — no point paying the idempotent-producer latency tax. Overridable via `@Bean("dltKafkaTemplate")`. |

## Listener pattern

**One rule**: `recordProcessed` must commit in the same transaction as the business write. Crash between commits → duplicate-processing window. Reactive: wrap with `TransactionalOperator.transactional(...)`.

```java
@Component
@RequiredArgsConstructor
public class OrderEventListener {

  private final OrderService orderService;
  private final OutboxConsumerIdempotency idempotency;
  private final TransactionalOperator tx;

  @KafkaListener(topics = "orders.created", groupId = "${spring.application.name}")
  public Mono<Void> onCreated(
      @Payload OrderCreatedEvent event,
      @Header(KafkaHeaders.RECEIVED_TOPIC) String topic,
      @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
      @Header("ob.lsn") long lsn,
      @Header(value = "ob.eid", required = false) String eid) {

    var ctx = new IdempotencyContext(
        "${spring.application.name}", topic, partition, lsn, eid);

    return idempotency.isProcessed(ctx)
        .flatMap(seen -> seen
            ? Mono.empty()
            : orderService.handle(event)
                .then(idempotency.recordProcessed(ctx)))
        .as(tx::transactional);
  }
}
```

Imperative consumers use `@Transactional` instead — same rule, same wiring.

## Error handling (`DefaultErrorHandler` + DLT)

Autoconfigure wires:

- **Exponential-backoff retry** (`ExponentialBackOffWithMaxRetries`). Retries up to `maxAttempts`; delay = `initialInterval × multiplier^(n-1)` capped at `maxInterval`.
- On exhaustion, `DeadLetterPublishingRecoverer` forwards to `<topic>.DLT` via `dltKafkaTemplate`.

```yaml
f8a:
  kafka:
    consumer:
      idempotency:
        enabled: true                # default; presence of the dep is the real switch
        validate-on-startup: true
      retry:
        max-attempts: 3
        initial-interval: 1s
        multiplier: 2.0
        max-interval: 30s
```

### Marking exceptions non-retryable

Register a `DefaultErrorHandlerCustomizer` bean — don't replace the whole handler:

```java
@Bean
DefaultErrorHandlerCustomizer markValidationFatal() {
  return handler -> handler.addNotRetryableExceptions(
      MethodArgumentNotValidException.class,
      DeserializationException.class);
}
```

### Custom DLT producer

Override default fire-and-forget template only if idempotence on DLT writes needed (rare):

```java
@Bean("dltKafkaTemplate")
KafkaTemplate<?, ?> dltKafkaTemplate(ProducerFactory<?, ?> pf) {
  KafkaTemplate<?, ?> t = new KafkaTemplate<>(pf);
  t.setObservationEnabled(true);
  return t;
}
```

## JSON consumer factory helpers

For typed `ConcurrentKafkaListenerContainerFactory` instead of Spring Boot default:

```java
@Bean("orderListenerContainerFactory")
ConcurrentKafkaListenerContainerFactory<String, OrderCreatedEvent> orderListenerFactory(
    KafkaProperties props, DefaultErrorHandler errorHandler) {
  var cf = SummerKafkaConsumerFactories.jsonConsumerFactory(
      props, OrderCreatedEvent.class);
  return SummerKafkaConsumerFactories.jsonListenerContainerFactory(props, cf, errorHandler);
}
```

Reference from listener: `@KafkaListener(topics = "...", containerFactory = "orderListenerContainerFactory")`.

## Gradle

```gradle
implementation 'io.f8a.summer:summer-kafka-consumer'
implementation 'io.f8a.summer:summer-kafka-consumer-autoconfigure'
implementation 'io.f8a.summer:summer-data-r2dbc'   // for R2dbcOutboxConsumerIdempotency
```

## Rules

- **Always** call `idempotency.recordProcessed(ctx)` in the **same reactive transaction** as the business write. Separate `.subscribe()` or `flatMap` outside transaction breaks the contract.
- **Never** skip watermark validator. Missing/misshapen `outbox_consumer_watermark` → silently re-processes from offset 0 on restart.
- **Never** invent own `(consumerGroup, topic, partition)` keying. Use `KafkaHeaders.RECEIVED_TOPIC`/`RECEIVED_PARTITION` directly — not static `topics =` value (misleading for pattern listeners).
- **Always** bind `@Header("ob.lsn") long` — 8-byte big-endian since 0.3.1. Older string-encoded headers produce wrong values silently. Producers must be on `summer-data-outbox` 0.3.1+.
- **Always** point DLT consumers at `<topic>.DLT` — where `DeadLetterPublishingRecoverer` writes.
- **Never** set `idempotency.enabled=true` without the dependency — no effect without autoconfigure jar.

## References

- **[references/versions/0.3.1.md](references/versions/0.3.1.md)** — module introduction + `ob.lsn` binary header change
- **[references/listener-examples.md](references/listener-examples.md)** — full listener wiring, imperative-mode, multi-topic patterns

Full feature × version table: [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md)

## Related Skills

- **summer-data** — producer side (`OutboxService.saveEvent`, `KafkaOutboxPublisher`, `ob.lsn` header)
- **summer-core** — gate; `Txid`/`Ufid` types in event payloads
- **summer-rest** — handlers that initiate writes published via outbox
