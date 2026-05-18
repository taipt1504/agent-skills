---
name: summer-messaging
description: SUMMER-SPECIFIC. Outbox + Kafka cluster standards — domain events via Summer OutboxService in same transaction, AbstractKafkaMessageHandler + MessageHandlerRegistry dispatch. Loaded ONLY when project uses io.f8a.summer.
globs: "*.java"
applicability:
  always: false
  requires_summer: true
  triggers:
    project_profile: ["summer:true"]
    files_match: ["**/*EventPublisher*.java", "**/*Listener*.java", "**/*Consumer*.java", "**/*Producer*.java", "**/*Outbox*.java"]
    code_patterns: ["OutboxService", "KafkaTemplate", "@KafkaListener", "AbstractKafkaMessageHandler", "MessageHandlerRegistry", "ProducerRecord"]
    task_keywords: ["event", "Kafka", "outbox", "DLQ", "idempotent", "topic", "consumer", "publisher"]
    related_rules:
      - rules/java/security.md
      - rules/java/observability.md
      - rules/summer/audit.md
relevance_assessment: |
  HIGH 90%+: Summer project (verified io.f8a.summer in build.gradle) AND event publishing or consumer code
  MEDIUM 40-79%: Summer project, handler that may publish events
  LOW 1-39%: Summer project, tangential touch (e.g., reads event payload)
  ZERO: project does NOT use Summer — generic Kafka rules apply, see skills/messaging-patterns instead
---

# Messaging Standards — Outbox + Kafka

## Rule 1 — Producer goes through Outbox (HARD BLOCK)

Domain event publish MUST use `OutboxService.saveEvent(...)` in same transaction as domain write. NEVER call `KafkaTemplate.send(...)` / `KafkaProducer.send(...)` direct from handler / service.

```java
import io.f8a.summer.core.outbox.OutboxService;

@Component
@RequiredArgsConstructor
public class CreateOrderHandler {
    private final OrderRepository repo;
    private final OutboxService outboxService;

    @Transactional
    public Mono<Order> handle(CreateOrderCommand cmd) {
        return repo.save(buildOrder(cmd))
            .flatMap(saved -> outboxService.saveEvent(
                saved.id(),
                "OrderCreated",
                new OrderCreatedEvent(saved.id(), saved.createdBy(), Instant.now())
            ).thenReturn(saved));
    }
}
```

Why: same-transaction guarantee — Kafka send + DB commit cannot diverge.

## Rule 2 — Outbox dispatcher publishes to Kafka

Background dispatcher reads outbox table, publishes to Kafka with retry + DLQ. `OutboxEventPublisher` per service routes eventType → channel.

## Rule 3 — Consumer pattern (reactor-kafka + handler registry)

```java
public abstract class AbstractKafkaMessageHandler<T> {
    public abstract Mono<Void> handle(T event);
    public abstract Class<T> eventType();
}

@Component
public class OrderCreatedHandler extends AbstractKafkaMessageHandler<OrderCreatedEvent> {
    private final NotificationService notificationService;

    @Override
    public Mono<Void> handle(OrderCreatedEvent event) {
        return notificationService.sendOrderConfirmation(event);
    }

    @Override
    public Class<OrderCreatedEvent> eventType() { return OrderCreatedEvent.class; }
}
```

`MessageHandlerRegistry` dispatches incoming records to matching handler by `eventType`.

## Rule 4 — Envelope schema

Every event payload MUST be wrapped:


```json
{
  "eventId": "<uuid>",
  "eventType": "OrderCreated",
  "occurredAt": "<ISO-8601>",
  "aggregateId": "<id>",
  "payload": { ... }
}
```

`eventId` → idempotency. `eventType` → registry dispatch. `occurredAt` → event-time ordering.

## Rule 5 — Topic naming

Pattern: `{bounded-context}.{aggregate}.{event-category}.v{n}`

Examples:
- `order.order.created.v1`
- `payment.transaction.refunded.v1`
- `user.profile.updated.v2`

Version in topic name — breaking schema change creates new topic; old consumers drain old topic.

## Rule 6 — DLQ per topic

Every topic has `{topic}.dlq`. After max retries (default 3), message moves to DLQ. DLQ consumer alerts ops — never auto-replay without manual review.

```yaml
# application.yml
kafka:
  consumer:
    max-retries: 3
    dlq-suffix: ".dlq"
```

## Rule 7 — Consumers MUST be idempotent

Same event N times → same final state. Strategies:
- **Dedup table:** write `(eventId, processed_at)` before side effect. Retry checks table.
- **Idempotent operations:** `INSERT ... ON CONFLICT DO NOTHING`, `UPDATE ... WHERE state = 'expected'`.
- **Optimistic locking:** version column on aggregate, retry on stale.

## Rule 8 — Anti-patterns

| Anti-pattern | Fix |
|---|---|
| `KafkaTemplate.send()` direct in service | Use `OutboxService.saveEvent()` in same tx |
| Event payload without envelope (just `aggregate` field) | Wrap in `{eventId, eventType, occurredAt, payload}` |
| Topic name without version (`order.created`) | Add `.v1` |
| Consumer without idempotency | Add dedup table or idempotent SQL |
| Auto-replay from DLQ on schedule | Manual review only |
| Read DB inside Kafka consumer to enrich event | Pre-enrich in publisher; consumer stays pure |
| Synchronous Kafka send blocking domain transaction | Outbox decouples — domain commits, dispatcher publishes async |

## Related

- `skills/messaging-patterns` — generic Kafka / RabbitMQ patterns
- `skills/summer-kafka` — Summer outbox + dispatcher specifics
- `skills/summer-data` — `OutboxService` implementation
- `rules/summer/audit.md` — caller propagation across event boundary
- `rules/java/security.md` — sensitive payload masking
