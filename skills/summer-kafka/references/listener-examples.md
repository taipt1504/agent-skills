# `summer-kafka` — Listener recipes

## 1. Reactive listener — single topic

```java
@Component
@RequiredArgsConstructor
public class TransferPostedListener {

  private final TransferService transferService;
  private final OutboxConsumerIdempotency idempotency;
  private final TransactionalOperator tx;

  @KafkaListener(topics = "ledger.transfer.posted", groupId = "${spring.application.name}")
  public Mono<Void> onPosted(
      @Payload LedgerTransferEvent event,
      @Header(KafkaHeaders.RECEIVED_TOPIC) String topic,
      @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
      @Header("ob.lsn") long lsn,
      @Header(value = "ob.eid", required = false) String eid) {

    var ctx = new IdempotencyContext(
        "${spring.application.name}", topic, partition, lsn, eid);

    return idempotency.isProcessed(ctx)
        .flatMap(seen -> seen
            ? Mono.empty()
            : transferService.applyPosted(event)
                .then(idempotency.recordProcessed(ctx)))
        .as(tx::transactional);
  }
}
```

The `.as(tx::transactional)` boundary is **load-bearing**. A chained `recordProcessed(...).subscribe()` outside the transaction breaks the contract — a crash between business commit and watermark commit produces a duplicate-processing window.

## 2. Imperative listener (non-reactive services)

```java
@KafkaListener(topics = "...")
@Transactional
public void onPosted(LedgerTransferEvent e, /* headers... */) {
  var ctx = new IdempotencyContext(group, topic, partition, lsn, eid);
  if (Boolean.TRUE.equals(idempotency.isProcessed(ctx).block())) return;
  transferService.applyPostedBlocking(e);
  idempotency.recordProcessed(ctx).block();
}
```

(`.block()` is unavoidable in imperative mode but safe inside `@Transactional` because Spring binds the R2DBC connection to the calling thread.)

## 3. Multi-topic listener (pattern subscription)

A single listener subscribed to several topics keeps its own per-topic watermark — the keying is by `(group, topic, partition)`, so the same listener method handles multiple topics correctly:

```java
@KafkaListener(topicPattern = "ledger\\.transfer\\.(posted|voided|reversed)",
               groupId = "${spring.application.name}")
public Mono<Void> onLedgerEvent(/* same headers as above */) {
  // ctx.topic() is the actual delivered topic — DO NOT hard-code a topic name here
  ...
}
```

Always read `KafkaHeaders.RECEIVED_TOPIC` rather than the static `topics =` attribute when building `IdempotencyContext` — pattern listeners and topic-list listeners both demand it.

## 4. Marking exceptions non-retryable

```java
@Bean
DefaultErrorHandlerCustomizer markValidationFatal() {
  return handler -> handler.addNotRetryableExceptions(
      MethodArgumentNotValidException.class,
      DeserializationException.class,
      ConstraintViolationException.class);
}
```

Listed exceptions skip the backoff schedule and go straight to `<topic>.DLT`.

## 5. Typed JSON container factory

```java
@Configuration
class ListenerConfig {
  @Bean("transferListenerContainerFactory")
  ConcurrentKafkaListenerContainerFactory<String, LedgerTransferEvent> transferListenerFactory(
      KafkaProperties props, DefaultErrorHandler errorHandler) {
    var cf = SummerKafkaConsumerFactories.jsonConsumerFactory(props, LedgerTransferEvent.class);
    return SummerKafkaConsumerFactories.jsonListenerContainerFactory(props, cf, errorHandler);
  }
}

@KafkaListener(topics = "ledger.transfer.posted",
               containerFactory = "transferListenerContainerFactory")
public Mono<Void> onPosted(...) { ... }
```

Use this only when the Spring Boot default factory doesn't suit (need typed deserialization without `JsonDeserializer.trusted.packages`, or per-listener concurrency tuning).

## 6. DLT consumer

Listen on `<topic>.DLT` with a different group id; **do not** use `OutboxConsumerIdempotency` here — the DLT is a sink, not a re-processable source:

```java
@KafkaListener(topics = "ledger.transfer.posted.DLT", groupId = "dlt-monitor")
public void onDlt(ConsumerRecord<String, byte[]> record) {
  log.error("DLT record: topic={} partition={} offset={} key={} size={}",
      record.topic(), record.partition(), record.offset(), record.key(), record.value().length);
  // forward to alerting / store to a triage table
}
```

## Gotchas

- **The dependency is the switch.** `f8a.kafka.consumer.idempotency.enabled=true` does nothing without `summer-kafka-consumer-autoconfigure` on the classpath. Conversely, dropping the autoconfigure dep silently disables idempotency — make sure the test classpath matches prod.
- **Scheduler-mode publishers** emit `createdAt.toEpochNanos()` as `ob.lsn` — fine under normal load, not strictly monotonic under extreme concurrency. For strict ordering, publish via CDC mode (see `summer-data`).
- **Consumer group rename = fresh watermark.** Renaming `group.id` creates a new watermark row; the new group will re-process from `auto-offset-reset` (default `earliest` for Summer-managed factories). Plan migrations accordingly.
- **`@Header("ob.lsn") long`** binds the header value via Spring Messaging's default `byte[] → Long` converter. Older producers emitting decimal strings silently produce wrong values — confirm producers are on `summer-data-outbox` 0.3.1+.
- **Same transaction or it doesn't count.** Reactive: `.as(tx::transactional)` around `flatMap(seen → process → recordProcessed)`. Imperative: `@Transactional` on the method. Never put `recordProcessed` in `doOnSuccess` or a separate `.subscribe()`.
