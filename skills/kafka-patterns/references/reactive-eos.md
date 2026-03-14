# Reactive Kafka & Exactly-Once Semantics Reference

ReactiveKafkaProducerTemplate, ReactiveKafkaConsumerTemplate, manual commit, and full EOS.

## Table of Contents
- [Reactive Kafka Dependencies](#reactive-kafka-dependencies)
- [Reactive Producer](#reactive-producer)
- [Reactive Consumer](#reactive-consumer)
- [Manual Offset Commit](#manual-offset-commit)
- [Exactly-Once Semantics — Full Config](#exactly-once-semantics--full-config)
- [Reactive Transactional Producer-Consumer](#reactive-transactional-producer-consumer)
- [Error Handling in Reactive Consumer](#error-handling-in-reactive-consumer)

---

## Reactive Kafka Dependencies

```xml
<dependency>
    <groupId>io.projectreactor.kafka</groupId>
    <artifactId>reactor-kafka</artifactId>
</dependency>
```

---

## Reactive Producer

```java
@Configuration
public class ReactiveKafkaProducerConfig {
    @Bean
    public ReactiveKafkaProducerTemplate<String, Object> reactiveProducer(KafkaProperties props) {
        Map<String, Object> config = props.buildProducerProperties(null);
        config.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        config.put(ProducerConfig.ACKS_CONFIG, "all");
        config.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);
        return new ReactiveKafkaProducerTemplate<>(SenderOptions.create(config));
    }
}

@Service @RequiredArgsConstructor @Slf4j
public class ReactiveOrderProducer {
    private final ReactiveKafkaProducerTemplate<String, Object> producer;

    // Single record
    public Mono<Void> sendOrderEvent(String orderId, OrderEvent event) {
        return producer.send("order-events", orderId, event)
            .doOnNext(result -> {
                if (result.exception() != null)
                    log.error("Send failed for orderId={}", orderId, result.exception());
                else
                    log.debug("Sent to partition={} offset={}",
                        result.recordMetadata().partition(),
                        result.recordMetadata().offset());
            })
            .then();
    }

    // Batch of records — concurrent send
    public Mono<Void> sendBatch(List<OrderEvent> events) {
        return Flux.fromIterable(events)
            .flatMap(event -> producer.send("order-events", event.orderId(), event))
            .doOnNext(result -> {
                if (result.exception() != null) log.error("Batch send failed", result.exception());
            })
            .then();
    }

    // Send with explicit SenderRecord for more control
    public Mono<Void> sendWithCorrelation(OrderEvent event) {
        SenderRecord<String, Object, String> record = SenderRecord.create(
            "order-events", null, System.currentTimeMillis(),
            event.orderId(), event, event.correlationId());
        return producer.send(record)
            .doOnNext(r -> log.debug("Sent correlationId={}", r.correlationMetadata()))
            .then();
    }
}
```

---

## Reactive Consumer

```java
@Configuration
public class ReactiveKafkaConsumerConfig {
    @Bean
    public ReactiveKafkaConsumerTemplate<String, OrderEvent> reactiveConsumer(KafkaProperties props) {
        Map<String, Object> config = props.buildConsumerProperties(null);
        config.put(ConsumerConfig.GROUP_ID_CONFIG, "reactive-order-processor");
        config.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        config.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);  // manual commit
        config.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 100);
        config.put(ConsumerConfig.ISOLATION_LEVEL_CONFIG, "read_committed");

        ReceiverOptions<String, OrderEvent> options = ReceiverOptions
            .<String, OrderEvent>create(config)
            .subscription(Collections.singleton("order-events"))
            .pollTimeout(Duration.ofMillis(100));

        return new ReactiveKafkaConsumerTemplate<>(options);
    }
}

@Service @RequiredArgsConstructor @Slf4j
public class ReactiveOrderConsumer {
    private final ReactiveKafkaConsumerTemplate<String, OrderEvent> consumer;
    private final OrderService orderService;

    @PostConstruct
    public void startConsuming() {
        consumer.receiveAutoAck()   // auto-commits after each record
            .flatMap(record -> orderService.process(record.value())
                .doOnError(ex -> log.error("Failed to process {}", record.key(), ex))
                .onErrorResume(ex -> Mono.empty()))  // skip failed records
            .subscribe(
                result -> log.debug("Processed: {}", result),
                ex -> log.error("Consumer error", ex));
    }
}
```

---

## Manual Offset Commit

```java
@Service @RequiredArgsConstructor @Slf4j
public class ManualCommitConsumer {
    private final ReactiveKafkaConsumerTemplate<String, OrderEvent> consumer;

    @PostConstruct
    public void startConsuming() {
        consumer.receive()  // ReceiverRecord — must manually ack
            .flatMap(record -> processRecord(record)
                .doOnSuccess(v -> record.receiverOffset().acknowledge())  // ← manual ack
                .doOnError(ex -> log.error("Failed, not acking: {}", record.key(), ex))
                .onErrorResume(ex -> Mono.empty()))
            .retryWhen(Retry.backoff(Long.MAX_VALUE, Duration.ofSeconds(1))
                .maxBackoff(Duration.ofMinutes(1)))
            .subscribe();
    }

    // Batch commit for efficiency
    @PostConstruct
    public void startBatchConsuming() {
        consumer.receive()
            .window(100)  // commit every 100 records
            .flatMap(batch -> batch
                .flatMap(record -> processRecord(record).thenReturn(record))
                .collectList()
                .doOnNext(records -> {
                    // Acknowledge the last record's offset (commits all prior offsets)
                    if (!records.isEmpty())
                        records.get(records.size() - 1).receiverOffset().commit().subscribe();
                }))
            .subscribe();
    }

    private Mono<Void> processRecord(ReceiverRecord<String, OrderEvent> record) {
        return orderService.process(record.value());
    }
}
```

---

## Exactly-Once Semantics — Full Config

### application.yml

```yaml
spring:
  kafka:
    producer:
      acks: all
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
      properties:
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5
        retries: 2147483647
      transaction-id-prefix: "eos-tx-"

    consumer:
      group-id: eos-consumer-group
      auto-offset-reset: earliest
      enable-auto-commit: false
      isolation-level: read_committed
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
      properties:
        spring.json.trusted.packages: "com.example.events"
```

### Config Class

```java
@Configuration
public class EosKafkaConfig {
    @Bean
    public ProducerFactory<String, Object> eosProducerFactory(KafkaProperties props) {
        var config = props.buildProducerProperties(null);
        config.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        config.put(ProducerConfig.ACKS_CONFIG, "all");
        config.put(ProducerConfig.RETRIES_CONFIG, Integer.MAX_VALUE);
        config.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);
        var factory = new DefaultKafkaProducerFactory<String, Object>(config);
        factory.setTransactionalIdPrefix("eos-tx-");
        return factory;
    }

    @Bean
    public KafkaTransactionManager<String, Object> kafkaTransactionManager(
            ProducerFactory<String, Object> factory) {
        return new KafkaTransactionManager<>(factory);
    }
}
```

---

## Reactive Transactional Producer-Consumer

```java
// Consume from one topic, process, produce to another — atomically
@Service @RequiredArgsConstructor
public class EosTransformer {
    private final ReactiveKafkaConsumerTemplate<String, RawOrder> consumer;
    private final ReactiveKafkaProducerTemplate<String, EnrichedOrder> producer;

    @PostConstruct
    public void start() {
        consumer.receive()
            .flatMap(record -> enrich(record.value())
                .flatMap(enriched ->
                    // Send + commit offset in same transaction
                    producer.sendTransactionally(SenderRecord.create(
                        "enriched-orders", null, null, record.key(), enriched, null))
                    .doOnNext(r -> record.receiverOffset().acknowledge())
                ))
            .subscribe();
    }

    private Mono<EnrichedOrder> enrich(RawOrder raw) {
        return Mono.just(new EnrichedOrder(raw.id(), raw.customerId(), /* enriched data */ null));
    }
}
```

---

## Error Handling in Reactive Consumer

```java
@Service @RequiredArgsConstructor
public class ResilientReactiveConsumer {
    private final ReactiveKafkaConsumerTemplate<String, OrderEvent> consumer;
    private final DeadLetterProducer dlqProducer;

    @PostConstruct
    public void start() {
        consumer.receive()
            .flatMap(record -> processWithRetry(record), 4)  // max 4 concurrent
            .subscribe(
                r -> log.debug("Processed successfully"),
                ex -> log.error("Fatal consumer error — restarting", ex));
    }

    private Mono<Void> processWithRetry(ReceiverRecord<String, OrderEvent> record) {
        return orderService.process(record.value())
            .retryWhen(Retry.backoff(2, Duration.ofMillis(500))
                .filter(ex -> ex instanceof TransientException))
            .doOnSuccess(v -> record.receiverOffset().acknowledge())
            .onErrorResume(ex -> {
                log.error("Sending to DLQ: {}", record.key(), ex);
                return dlqProducer.send("order-events.DLT", record.key(),
                    new DeadLetterEvent(record.value(), ex.getMessage()))
                    .then(Mono.fromRunnable(() -> record.receiverOffset().acknowledge()));
            });
    }
}
```
