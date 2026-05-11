---
name: summer-kafka
description: Summer Framework Kafka consumer module (0.3.1+) — LSN-watermark idempotency for outbox-driven consumers, default DefaultErrorHandler with exponential-backoff retry + DLT, JSON consumer factory helpers, dedicated dltKafkaTemplate. Use when wiring @KafkaListener handlers that consume Summer outbox events (ob.lsn header) and need at-least-once-with-skip semantics without per-event dedup tables.
triggers:
  natural: ["kafka consumer idempotency", "outbox consumer", "lsn watermark", "summer kafka", "kafka dlt", "kafka retry summer"]
  code: ["OutboxConsumerIdempotency", "IdempotencyContext", "SummerKafkaConsumerFactories", "DefaultErrorHandlerCustomizer", "ConsumerWatermarkValidator", "f8a.kafka.consumer", "outbox_consumer_watermark"]
requires: ["summer-core", "summer-data"]
---

# Summer Kafka — Consumer Idempotency & Error Handling

**Gate:** Verify summer-core is loaded and `io.f8a.summer:summer-platform` is in build.gradle before proceeding. Producers should already be on `summer-data-outbox` 0.3.1+ so messages carry the `ob.lsn` header.

**Modules:** `summer-kafka-consumer` | `summer-kafka-consumer-autoconfigure` (both added 0.3.1)
**Package:** `io.f8a.summer.kafka.consumer.*`
**Activation:** Auto when `summer-kafka-consumer-autoconfigure` is on the classpath. **There is no `enabled` flag — presence of the dependency is the opt-in.** Disable by dropping the dependency.

**This SKILL.md tracks LATEST stable (0.3.5).** First shipped in 0.3.1; no separate overlay for 0.3.5 (no kafka-consumer changes since 0.3.1).

## Why it exists

Pre-0.3.1 every consumer rolled its own dedup table (one row per event) or relied on a domain-unique key + `DuplicateKeyException`. Both scale with **message volume** and produce hot indexes. Summer's `OutboxConsumerIdempotency` watermarks by `(consumer_group, topic, partition)` — matching Kafka's native offset granularity — so storage cost is O(groups × topics × partitions), typically under a few hundred rows per service, regardless of throughput.

The contract works because Debezium preserves PostgreSQL LSN order **within** a Kafka topic-partition. Scheduler-mode publishers emit `createdAt.toEpochNanos()` as a best-effort substitute — stable under normal load, not authoritative under extreme concurrency. Strict ordering ⇒ publish via CDC mode.

## Schema — `outbox_consumer_watermark`

One row per consuming `(group, topic, partition)`. Schema must exist before consumers run; `ConsumerWatermarkValidator` checks it on startup (disable: `f8a.kafka.consumer.idempotency.validate-on-startup=false`).

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

**Column names are load-bearing** — `ConsumerWatermarkValidator` checks for exactly `consumer_group`, `topic`, `partition`, `last_lsn`, `last_event_id`, `last_updated_at`. A migration that uses `lsn` / `updated_at` instead will fail boot. DDL also lives in `summer-data/references/ddl-scripts.md`.

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

The **one rule**: `recordProcessed` must commit in the same transaction as the business write. Otherwise a crash between commits produces a duplicate-processing window. Reactive: wrap with `TransactionalOperator.transactional(...)`.

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

The autoconfigure wires:

- **Exponential-backoff retry** matching Spring Kafka's `ExponentialBackOffWithMaxRetries`. Each failed record retries up to `maxAttempts` times, with `initialInterval × multiplier^(n-1)` delay (capped at `maxInterval`).
- On exhaustion, `DeadLetterPublishingRecoverer` forwards the record to `<topic>.DLT` via `dltKafkaTemplate`.

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

Don't replace the whole handler — register a `DefaultErrorHandlerCustomizer` bean:

```java
@Bean
DefaultErrorHandlerCustomizer markValidationFatal() {
  return handler -> handler.addNotRetryableExceptions(
      MethodArgumentNotValidException.class,
      DeserializationException.class);
}
```

### Custom DLT producer

Override the default fire-and-forget template if you need idempotence on DLT writes (rare):

```java
@Bean("dltKafkaTemplate")
KafkaTemplate<?, ?> dltKafkaTemplate(ProducerFactory<?, ?> pf) {
  KafkaTemplate<?, ?> t = new KafkaTemplate<>(pf);
  t.setObservationEnabled(true);
  return t;
}
```

## JSON consumer factory helpers

For services that need a typed `ConcurrentKafkaListenerContainerFactory` instead of the Spring Boot default:

```java
@Bean("orderListenerContainerFactory")
ConcurrentKafkaListenerContainerFactory<String, OrderCreatedEvent> orderListenerFactory(
    KafkaProperties props, DefaultErrorHandler errorHandler) {
  var cf = SummerKafkaConsumerFactories.jsonConsumerFactory(
      props, OrderCreatedEvent.class);
  return SummerKafkaConsumerFactories.jsonListenerContainerFactory(props, cf, errorHandler);
}
```

Reference it from the listener: `@KafkaListener(topics = "...", containerFactory = "orderListenerContainerFactory")`.

## Gradle

```gradle
implementation 'io.f8a.summer:summer-kafka-consumer'
implementation 'io.f8a.summer:summer-kafka-consumer-autoconfigure'
implementation 'io.f8a.summer:summer-data-r2dbc'   // for R2dbcOutboxConsumerIdempotency
```

## Rules

- **Always** call `idempotency.recordProcessed(ctx)` in the **same reactive transaction** as the business write. A separate `.subscribe()` or chained `flatMap` outside the transaction breaks the contract.
- **Never** skip the watermark validator. A consumer started against a missing/misshapen `outbox_consumer_watermark` table will silently re-process from offset 0 on every restart.
- **Never** invent your own `(consumerGroup, topic, partition)` keying — that's the contract; use `KafkaHeaders.RECEIVED_TOPIC` / `RECEIVED_PARTITION` directly, not the listener's static `topics =` value (which is misleading for pattern listeners).
- **Always** bind `@Header("ob.lsn") long` — 8-byte big-endian since 0.3.1, decoded by Spring Messaging's default `byte[] → Long` converter. Older string-encoded headers produce wrong values silently — make sure producers are on `summer-data-outbox` 0.3.1+.
- **Always** point DLT consumers at `<topic>.DLT` — that's where `DeadLetterPublishingRecoverer` writes.
- **Never** raise `idempotency.enabled=true` without the dependency; the property has no effect without the autoconfigure jar.

## References

- **[references/versions/0.3.1.md](references/versions/0.3.1.md)** — module introduction (and the `ob.lsn` binary header change).
- **[references/listener-examples.md](references/listener-examples.md)** — full listener wiring, including imperative-mode and multi-topic patterns.

For the full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Related Skills

- **summer-data** — producer side (`OutboxService.saveEvent`, `KafkaOutboxPublisher`, `ob.lsn` header).
- **summer-core** — gate; `Txid` / `Ufid` types appearing in event payloads.
- **summer-rest** — handlers that initiate writes which then publish via outbox.
