---
name: kafka-patterns
description: >
  Apache Kafka patterns for Java Spring Boot applications. Covers producer/consumer
  patterns, exactly-once semantics, reactive Kafka (reactor-kafka), error handling
  with DLT, Schema Registry, testing, monitoring, and production configuration.
  Use when implementing Kafka messaging in Spring Boot 3.x projects.
---

# Kafka Patterns for Spring Boot

Production-ready Kafka patterns for Java 17+ / Spring Boot 3.x.

## When to Activate

- Implementing Kafka producers or consumers
- Configuring exactly-once semantics or idempotent producers
- Setting up dead letter topics (DLT) and error handling
- Reviewing Kafka integration code for reliability patterns

## Pre-Deploy Verification Checklist

- [ ] Producer uses idempotent mode (`enable.idempotence=true`)
- [ ] Consumer group ID is meaningful and unique per service
- [ ] Dead letter topic configured for failed messages
- [ ] Error handler with retry + DLT fallback
- [ ] Serializer/deserializer configured (not relying on defaults)
- [ ] Consumer offset commit strategy explicit (manual or auto)
- [ ] Topic partitioning strategy documented
- [ ] Testcontainers test for producer/consumer round-trip

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

## Essential Configuration

### Producer (application.yml)

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

### Consumer (application.yml)

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

## Producer Patterns

```java
@Service @RequiredArgsConstructor
public class OrderEventProducer {
    private final KafkaTemplate<String, Object> kafkaTemplate;

    // Async (fire-and-forget with callback)
    public void sendAsync(String topic, String key, Object payload) {
        kafkaTemplate.send(topic, key, payload)
            .whenComplete((result, ex) -> {
                if (ex != null) log.error("Failed key={}", key, ex);
                else log.debug("Sent key={} offset={}", key, result.getRecordMetadata().offset());
            });
    }

    // Sync (blocks until acknowledged)
    public SendResult<String, Object> sendSync(String topic, String key, Object payload) {
        try {
            return kafkaTemplate.send(topic, key, payload).get(10, TimeUnit.SECONDS);
        } catch (ExecutionException e) { throw new KafkaPublishException("Broker rejected", e.getCause()); }
        catch (TimeoutException e) { throw new KafkaPublishException("Send timed out", e); }
        catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new KafkaPublishException("Interrupted", e); }
    }
}
```

## Consumer Pattern (Manual Ack)

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
        throw e;                 // don't ack — message will be redelivered
    } catch (Exception e) {
        log.error("Fatal error", e);
        ack.acknowledge();       // ack to skip poison pill; DLT handles it
    }
}
```

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

## Key Design Decisions

| Decision | Recommendation |
|----------|---------------|
| Key selection | Business key (orderId) — ensures ordering per entity |
| Partitions | 6-12 per topic to start |
| Replication | 3 replicas, min.insync.replicas=2 |
| Consumer commit | Manual after processing — prevents data loss |
| Error strategy | DefaultErrorHandler + DLT — retries transient, dead-letters permanent |
| Serialization | JSON for simplicity, Avro for schema evolution |

## Anti-Patterns

```
❌ enable-auto-commit=true          → messages lost on crash before processing
❌ No DLT configured               → poison pill blocks entire partition forever
❌ Large messages (>1MB)           → use claim-check pattern (store in S3, send reference)
❌ Too many partitions (1000+)     → high memory, slow rebalance — start small, grow
❌ Missing max.poll.interval.ms    → consumer kicked from group if processing > 5min
❌ Ignoring consumer lag           → lag grows silently; alert when lag > 10K
```

## References

Load as needed:

- **[references/producers-consumers.md](references/producers-consumers.md)** — Transactional producer, batch consumer, consumer group strategies, idempotent processing
- **[references/reactive-eos.md](references/reactive-eos.md)** — Reactive Kafka (reactor-kafka), exactly-once semantics, Schema Registry (Avro/JSON)
- **[references/testing-monitoring.md](references/testing-monitoring.md)** — EmbeddedKafka, Testcontainers + Schema Registry, Micrometer metrics, consumer lag monitoring
