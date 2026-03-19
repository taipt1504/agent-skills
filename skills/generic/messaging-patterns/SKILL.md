---
name: messaging-patterns
description: >
  Kafka and RabbitMQ messaging patterns for Java Spring Boot 3.x. Covers producer
  reliability, consumer error handling, DLT/DLQ, reactive messaging, exchange/topic
  design, exactly-once semantics, and production configuration for both brokers.
triggers:
  - Kafka
  - RabbitMQ
  - "@KafkaListener"
  - "@RabbitListener"
  - producer
  - consumer
  - DLT
  - DLQ
  - dead letter
  - messaging
---

# Messaging Patterns for Spring Boot

Production-ready Kafka and RabbitMQ patterns for Java 17+ / Spring Boot 3.x.

## Decision Table: Kafka vs RabbitMQ

| Criteria | Kafka | RabbitMQ |
|----------|-------|----------|
| Throughput | Millions msg/s, append-only log | Tens of thousands msg/s |
| Ordering | Per-partition guaranteed | Per-queue (single consumer) |
| Replay | Yes -- consumers re-read by offset | No -- consumed messages removed |
| Routing | Topic-based (partitions) | Exchange-based (direct/topic/fanout/headers) |
| Delivery | At-least-once; exactly-once with EOS | At-least-once; no native EOS |
| Use when | Event streaming, log aggregation, high-volume CQRS | Task queues, RPC, complex routing, low-latency request/reply |
| Protocol | Custom binary | AMQP 0-9-1 |

**Rule of thumb:** Event log / replay needed -> Kafka. Complex routing / task dispatch -> RabbitMQ.

## Shared Patterns

### Producer Reliability
1. **Idempotent sends** -- Kafka: `enable.idempotence=true`; RabbitMQ: publisher confirms
2. **Persistent delivery** -- Kafka: `acks=all`; RabbitMQ: `PERSISTENT` delivery mode
3. **Transactional** -- Kafka: `executeInTransaction`; RabbitMQ: `rabbitTemplate.invoke`
4. **Serialization** -- Explicit serializer config (JSON/Avro); never rely on defaults

### Consumer Error Handling
1. **Manual ACK** -- both brokers; never auto-ack in production
2. **Retry + dead letter** -- Kafka: `DefaultErrorHandler` + `DeadLetterPublishingRecoverer`; RabbitMQ: `RetryInterceptorBuilder` + DLX/DLQ
3. **Non-retryable exceptions** -- skip retry for `DeserializationException`, `ValidationException`
4. **DLQ consumer** -- persist failed messages, always ACK DLQ to prevent loops

## Critical Config

### Kafka (application.yml)

```yaml
spring.kafka:
  producer:
    acks: all
    properties:
      enable.idempotence: true
      max.in.flight.requests.per.connection: 5
  consumer:
    enable-auto-commit: false
    properties:
      isolation.level: read_committed
      partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
```

### RabbitMQ (application.yml)

```yaml
spring.rabbitmq:
  publisher-confirm-type: correlated
  publisher-returns: true
  listener.simple:
    acknowledge-mode: manual
    prefetch: 10
    retry:
      enabled: true
      max-attempts: 3
      initial-interval: 1s
      multiplier: 2.0
```

## Verification Checklist

- [ ] Producer uses idempotent/confirmed mode
- [ ] Consumer ACK is manual (not auto)
- [ ] Dead letter configured (DLT for Kafka, DLX+DLQ for RabbitMQ)
- [ ] Retry with backoff before dead-lettering
- [ ] Non-retryable exceptions bypass retry
- [ ] Serializer/deserializer explicitly configured
- [ ] Testcontainers round-trip test for producer-consumer
- [ ] DLQ consumer or monitoring in place
- [ ] Consumer lag (Kafka) or queue depth (RabbitMQ) monitored
- [ ] Health indicator registered

## References

Load as needed:

- **[references/kafka.md](references/kafka.md)** -- Kafka producer/consumer patterns, DLT, topic config, exactly-once semantics, reactive Kafka, Schema Registry/Avro, anti-patterns
- **[references/rabbitmq.md](references/rabbitmq.md)** -- RabbitMQ exchange topology, producer confirms, consumer manual ACK, retry+DLQ with x-death, reactor-rabbitmq, production config, anti-patterns
- **[references/testing-monitoring.md](references/testing-monitoring.md)** -- EmbeddedKafka, Testcontainers (Kafka + RabbitMQ), Awaitility, consumer lag monitoring, health indicators, Micrometer metrics
