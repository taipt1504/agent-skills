# Kafka Producers & Consumers Reference

Detailed producer, consumer, exactly-once, and schema registry patterns.

## Table of Contents
- [Transactional Producer](#transactional-producer)
- [Producer with Headers](#producer-with-headers)
- [Batch Consumer](#batch-consumer)
- [Consumer Group Strategies](#consumer-group-strategies)
- [Idempotent Consumer](#idempotent-consumer)
- [Exactly-Once Semantics](#exactly-once-semantics)
- [Schema Registry — Avro](#schema-registry--avro)
- [Schema Compatibility Strategies](#schema-compatibility-strategies)

---

## Transactional Producer

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

    // All sends are committed atomically — any failure rolls back all
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

## Producer with Headers

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

## Batch Consumer

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
        // do NOT ack — entire batch will be redelivered
    }
}
```

## Consumer Group Strategies

| Strategy | Config | Use Case |
|----------|--------|----------|
| Range | `RangeAssignor` | Co-partitioned topics |
| RoundRobin | `RoundRobinAssignor` | Even distribution |
| Sticky | `StickyAssignor` | Minimizes movement during rebalance |
| CooperativeSticky | `CooperativeStickyAssignor` | **Recommended** — incremental rebalance |

```yaml
spring:
  kafka:
    consumer:
      properties:
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
        group.instance.id: ${HOSTNAME}  # static membership — avoids unnecessary rebalances
```

## Idempotent Consumer (Application-Level Deduplication)

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

## Exactly-Once Semantics

Requires: `enable.idempotence=true`, `acks=all`, `isolation.level=read_committed`

```yaml
spring:
  kafka:
    producer:
      acks: all
      properties:
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5
      transaction-id-prefix: "order-tx-"
    consumer:
      properties:
        isolation.level: read_committed
      enable-auto-commit: false
```

```java
// Consume-Transform-Produce within a transaction
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

## Schema Registry — Avro

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

## Schema Compatibility Strategies

| Strategy | Allowed Changes | Use Case |
|----------|----------------|----------|
| BACKWARD | Remove fields, add optional | **Default.** New consumer reads old data |
| FORWARD | Add fields, remove optional | Old consumer reads new data |
| FULL | Only add/remove optional | Both directions |
| NONE | Anything | Development only |
