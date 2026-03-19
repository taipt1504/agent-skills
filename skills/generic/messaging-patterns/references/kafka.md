# Kafka Patterns Reference

Comprehensive Kafka producer, consumer, error handling, reactive, and Schema Registry patterns.

## Table of Contents
- [Dependencies](#dependencies)
- [Producer Patterns](#producer-patterns)
- [Consumer Patterns](#consumer-patterns)
- [Error Handling (DLT)](#error-handling-dlt)
- [Topic Configuration](#topic-configuration)
- [Exactly-Once Semantics](#exactly-once-semantics)
- [Reactive Kafka (reactor-kafka)](#reactive-kafka-reactor-kafka)
- [Schema Registry / Avro](#schema-registry--avro)
- [Key Design Decisions](#key-design-decisions)
- [Anti-Patterns](#anti-patterns)

---

## Dependencies

```xml
<dependency>
    <groupId>org.springframework.kafka</groupId>
    <artifactId>spring-kafka</artifactId>
</dependency>
<!-- Reactive Kafka -->
<dependency>
    <groupId>io.projectreactor.kafka</groupId>
    <artifactId>reactor-kafka</artifactId>
</dependency>
<!-- Testing -->
<dependency>
    <groupId>org.springframework.kafka</groupId>
    <artifactId>spring-kafka-test</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>kafka</artifactId>
    <scope>test</scope>
</dependency>
```

---

## Producer Patterns

### Async Producer (fire-and-forget with callback)

```java
@Service @RequiredArgsConstructor
public class OrderEventProducer {
    private final KafkaTemplate<String, Object> kafkaTemplate;

    public void sendAsync(String topic, String key, Object payload) {
        kafkaTemplate.send(topic, key, payload)
            .whenComplete((result, ex) -> {
                if (ex != null) log.error("Failed key={}", key, ex);
                else log.debug("Sent key={} offset={}", key, result.getRecordMetadata().offset());
            });
    }
}
```

### Sync Producer (blocks until acknowledged)

```java
public SendResult<String, Object> sendSync(String topic, String key, Object payload) {
    try {
        return kafkaTemplate.send(topic, key, payload).get(10, TimeUnit.SECONDS);
    } catch (ExecutionException e) { throw new KafkaPublishException("Broker rejected", e.getCause()); }
    catch (TimeoutException e) { throw new KafkaPublishException("Send timed out", e); }
    catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new KafkaPublishException("Interrupted", e); }
}
```

### Transactional Producer (atomic multi-send)

```java
@Configuration
public class KafkaTransactionalConfig {
    @Bean
    public ProducerFactory<String, Object> producerFactory(KafkaProperties properties) {
        Map<String, Object> props = properties.buildProducerProperties(null);
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        var factory = new DefaultKafkaProducerFactory<String, Object>(props);
        factory.setTransactionalIdPrefix("order-tx-");
        return factory;
    }
}

@Service @RequiredArgsConstructor
public class TransactionalProducer {
    private final KafkaTemplate<String, Object> kafkaTemplate;

    // All sends committed atomically -- any failure rolls back all
    public void sendTransactional(Order order) {
        kafkaTemplate.executeInTransaction(ops -> {
            ops.send("orders", order.id(), new OrderCreatedEvent(order));
            ops.send("inventory", order.id(), new ReserveStockCommand(order.items()));
            ops.send("notifications", order.id(), new OrderNotification(order));
            return true;
        });
    }
}
```

### Producer with Headers

```java
public void sendWithHeaders(String topic, String key, Object payload,
                            Map<String, String> headers) {
    ProducerRecord<String, Object> record = new ProducerRecord<>(topic, key, payload);
    headers.forEach((k, v) -> record.headers().add(k, v.getBytes(StandardCharsets.UTF_8)));
    record.headers().add("X-Correlation-Id", UUID.randomUUID().toString().getBytes());
    record.headers().add("X-Source-Service", "order-service".getBytes());
    kafkaTemplate.send(record);
}
```

### Essential Producer Config (application.yml)

```yaml
spring:
  kafka:
    bootstrap-servers: kafka-1:9092,kafka-2:9092,kafka-3:9092
    producer:
      acks: all
      retries: 2147483647
      batch-size: 32768            # 32KB
      compression-type: lz4
      properties:
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5
        linger.ms: 20
        delivery.timeout.ms: 120000
```

---

## Consumer Patterns

### Manual Ack Consumer

```java
@Bean
public ConcurrentKafkaListenerContainerFactory<String, Object> kafkaListenerContainerFactory(
        ConsumerFactory<String, Object> consumerFactory) {
    var factory = new ConcurrentKafkaListenerContainerFactory<String, Object>();
    factory.setConsumerFactory(consumerFactory);
    factory.setConcurrency(3);
    factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.MANUAL_IMMEDIATE);
    return factory;
}

@KafkaListener(topics = "orders", groupId = "order-processor")
public void consume(@Payload OrderEvent event, Acknowledgment ack) {
    try {
        processOrder(event);
        ack.acknowledge();       // commit ONLY after successful processing
    } catch (RetryableException e) {
        throw e;                 // don't ack -- message will be redelivered
    } catch (Exception e) {
        log.error("Fatal error", e);
        ack.acknowledge();       // ack to skip poison pill; DLT handles it
    }
}
```

### Batch Consumer

```java
@Bean
public ConcurrentKafkaListenerContainerFactory<String, Object> batchListenerFactory(
        ConsumerFactory<String, Object> consumerFactory) {
    var factory = new ConcurrentKafkaListenerContainerFactory<String, Object>();
    factory.setConsumerFactory(consumerFactory);
    factory.setBatchListener(true);
    factory.setConcurrency(3);
    factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.MANUAL);
    return factory;
}

@KafkaListener(topics = "analytics-events", groupId = "analytics-batch",
               containerFactory = "batchListenerFactory")
public void consumeBatch(List<ConsumerRecord<String, AnalyticsEvent>> records,
                         Acknowledgment ack) {
    log.info("Received batch of {} records", records.size());
    try {
        List<AnalyticsEvent> events = records.stream().map(ConsumerRecord::value).toList();
        analyticsService.processBatch(events);
        ack.acknowledge();
    } catch (Exception e) {
        log.error("Batch processing failed", e);
        // do NOT ack -- entire batch will be redelivered
    }
}
```

### Consumer Group Strategies

| Strategy | Config | Use Case |
|----------|--------|----------|
| Range | `RangeAssignor` | Co-partitioned topics |
| RoundRobin | `RoundRobinAssignor` | Even distribution |
| Sticky | `StickyAssignor` | Minimizes movement during rebalance |
| CooperativeSticky | `CooperativeStickyAssignor` | **Recommended** -- incremental rebalance |

```yaml
spring:
  kafka:
    consumer:
      properties:
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
        group.instance.id: ${HOSTNAME}  # static membership -- avoids unnecessary rebalances
```

### Idempotent Consumer (Application-Level Deduplication)

```java
@Service @RequiredArgsConstructor
public class IdempotentOrderProcessor {
    private final ProcessedEventRepository processedEvents;
    private final OrderService orderService;

    @Transactional
    public void process(String eventId, OrderEvent event) {
        if (processedEvents.existsById(eventId)) {
            log.info("Event {} already processed, skipping", eventId);
            return;
        }
        orderService.handle(event);
        processedEvents.save(new ProcessedEvent(eventId, Instant.now()));
    }
}
```

### Essential Consumer Config (application.yml)

```yaml
spring:
  kafka:
    consumer:
      group-id: order-service
      auto-offset-reset: earliest
      enable-auto-commit: false     # always manual commit
      max-poll-records: 500
      properties:
        isolation.level: read_committed
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
        session.timeout.ms: 45000
        max.poll.interval.ms: 300000
```

---

## Error Handling (DLT)

```java
@Bean
public ConcurrentKafkaListenerContainerFactory<String, Object> kafkaListenerContainerFactory(
        ConsumerFactory<String, Object> consumerFactory,
        KafkaTemplate<String, Object> kafkaTemplate) {

    var errorHandler = new DefaultErrorHandler(
        new DeadLetterPublishingRecoverer(kafkaTemplate,
            (record, ex) -> new TopicPartition(record.topic() + ".DLT", record.partition())),
        new FixedBackOff(1000L, 3L)  // 3 retries at 1s interval
    );
    errorHandler.addNotRetryableExceptions(
        DeserializationException.class, ValidationException.class);

    var factory = new ConcurrentKafkaListenerContainerFactory<String, Object>();
    factory.setConsumerFactory(consumerFactory);
    factory.setCommonErrorHandler(errorHandler);
    return factory;
}
```

---

## Topic Configuration

```java
@Bean
public NewTopic ordersTopic() {
    return TopicBuilder.name("orders")
        .partitions(12).replicas(3)
        .config(TopicConfig.MIN_IN_SYNC_REPLICAS_CONFIG, "2")
        .config(TopicConfig.RETENTION_MS_CONFIG, String.valueOf(Duration.ofDays(7).toMillis()))
        .build();
}
```

---

## Exactly-Once Semantics

Requires: `enable.idempotence=true`, `acks=all`, `isolation.level=read_committed`, transactional producer.

### Full EOS Config (application.yml)

```yaml
spring:
  kafka:
    producer:
      acks: all
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
```

### EOS Config Bean

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

### Consume-Transform-Produce (transactional)

```java
@KafkaListener(topics = "raw-orders", groupId = "order-enricher")
public void processExactlyOnce(ConsumerRecord<String, RawOrder> record, Acknowledgment ack) {
    kafkaTemplate.executeInTransaction(ops -> {
        EnrichedOrder enriched = enrich(record.value());
        ops.send("enriched-orders", record.key(), enriched);
        ack.acknowledge(); // offset committed as part of transaction
        return null;
    });
}
```

---

## Reactive Kafka (reactor-kafka)

### Reactive Producer

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

    public Mono<Void> sendBatch(List<OrderEvent> events) {
        return Flux.fromIterable(events)
            .flatMap(event -> producer.send("order-events", event.orderId(), event))
            .doOnNext(result -> {
                if (result.exception() != null) log.error("Batch send failed", result.exception());
            })
            .then();
    }
}
```

### Reactive Consumer with Manual Commit

```java
@Configuration
public class ReactiveKafkaConsumerConfig {
    @Bean
    public ReactiveKafkaConsumerTemplate<String, OrderEvent> reactiveConsumer(KafkaProperties props) {
        Map<String, Object> config = props.buildConsumerProperties(null);
        config.put(ConsumerConfig.GROUP_ID_CONFIG, "reactive-order-processor");
        config.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        config.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
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
public class ManualCommitConsumer {
    private final ReactiveKafkaConsumerTemplate<String, OrderEvent> consumer;

    @PostConstruct
    public void startConsuming() {
        consumer.receive()  // ReceiverRecord -- must manually ack
            .flatMap(record -> processRecord(record)
                .doOnSuccess(v -> record.receiverOffset().acknowledge())
                .doOnError(ex -> log.error("Failed, not acking: {}", record.key(), ex))
                .onErrorResume(ex -> Mono.empty()))
            .retryWhen(Retry.backoff(Long.MAX_VALUE, Duration.ofSeconds(1))
                .maxBackoff(Duration.ofMinutes(1)))
            .subscribe();
    }

    private Mono<Void> processRecord(ReceiverRecord<String, OrderEvent> record) {
        return orderService.process(record.value());
    }
}
```

### Reactive Error Handling with DLT

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
                ex -> log.error("Fatal consumer error -- restarting", ex));
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

### Reactive Transactional Producer-Consumer

```java
@Service @RequiredArgsConstructor
public class EosTransformer {
    private final ReactiveKafkaConsumerTemplate<String, RawOrder> consumer;
    private final ReactiveKafkaProducerTemplate<String, EnrichedOrder> producer;

    @PostConstruct
    public void start() {
        consumer.receive()
            .flatMap(record -> enrich(record.value())
                .flatMap(enriched ->
                    producer.sendTransactionally(SenderRecord.create(
                        "enriched-orders", null, null, record.key(), enriched, null))
                    .doOnNext(r -> record.receiverOffset().acknowledge())
                ))
            .subscribe();
    }

    private Mono<EnrichedOrder> enrich(RawOrder raw) {
        return Mono.just(new EnrichedOrder(raw.id(), raw.customerId(), null));
    }
}
```

---

## Schema Registry / Avro

### Config (application.yml)

```yaml
spring:
  kafka:
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: io.confluent.kafka.serializers.KafkaAvroSerializer
      properties:
        schema.registry.url: http://schema-registry:8081
        auto.register.schemas: true
    consumer:
      value-deserializer: io.confluent.kafka.serializers.KafkaAvroDeserializer
      properties:
        schema.registry.url: http://schema-registry:8081
        specific.avro.reader: true
```

### Avro Schema Example

```json
{
  "type": "record",
  "name": "OrderEvent",
  "namespace": "com.example.events",
  "fields": [
    {"name": "orderId", "type": "string"},
    {"name": "customerId", "type": "string"},
    {"name": "amount", "type": {"type": "bytes", "logicalType": "decimal", "precision": 10, "scale": 2}},
    {"name": "status", "type": {"type": "enum", "name": "OrderStatus",
      "symbols": ["CREATED", "CONFIRMED", "SHIPPED", "DELIVERED", "CANCELLED"]}},
    {"name": "createdAt", "type": {"type": "long", "logicalType": "timestamp-millis"}},
    {"name": "metadata", "type": ["null", {"type": "map", "values": "string"}], "default": null}
  ]
}
```

### Schema Compatibility Strategies

| Strategy | Allowed Changes | Use Case |
|----------|----------------|----------|
| BACKWARD | Remove fields, add optional | **Default.** New consumer reads old data |
| FORWARD | Add fields, remove optional | Old consumer reads new data |
| FULL | Only add/remove optional | Both directions |
| NONE | Anything | Development only |

---

## Key Design Decisions

| Decision | Recommendation |
|----------|---------------|
| Key selection | Business key (orderId) -- ensures ordering per entity |
| Partitions | 6-12 per topic to start |
| Replication | 3 replicas, min.insync.replicas=2 |
| Consumer commit | Manual after processing -- prevents data loss |
| Error strategy | DefaultErrorHandler + DLT -- retries transient, dead-letters permanent |
| Serialization | JSON for simplicity, Avro for schema evolution |

---

## Anti-Patterns

| Anti-Pattern | Why It Fails |
|-------------|-------------|
| `enable-auto-commit=true` | Messages lost on crash before processing |
| No DLT configured | Poison pill blocks entire partition forever |
| Large messages (>1MB) | Use claim-check pattern (store in S3, send reference) |
| Too many partitions (1000+) | High memory, slow rebalance -- start small, grow |
| Missing `max.poll.interval.ms` | Consumer kicked from group if processing > 5min |
| Ignoring consumer lag | Lag grows silently; alert when lag > 10K |
| Auto-offset reset = `latest` in prod | Misses messages published while consumer was down |
| No idempotency in consumer | Duplicate processing on rebalance or retry |
