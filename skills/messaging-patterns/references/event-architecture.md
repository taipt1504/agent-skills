# Event Architecture — Saga, Outbox & Event Sourcing

## Event Types

| Type | Purpose | Example |
|------|---------|---------|
| **Domain Event** | Something happened in the domain | `OrderCreatedEvent` |
| **Integration Event** | Cross-service communication | `PaymentCompletedEvent` |
| **Command Event** | Request an action | `ProcessRefundCommand` |

## Saga Pattern — Choreography vs Orchestration

### Choreography (Event-Driven)

Each service listens for events and publishes the next. No central coordinator.

```
OrderService --[OrderCreated]--> PaymentService --[PaymentCompleted]--> InventoryService
                                 PaymentService --[PaymentFailed]----> OrderService (compensate)
```

```java
@Component
@RequiredArgsConstructor
public class PaymentEventListener {
    private final PaymentService paymentService;
    private final AuditService auditService;

    @KafkaListener(topics = "order.created", groupId = "payment-service")
    public void onOrderCreated(OrderCreatedEvent event) {
        paymentService.processPayment(event.orderId(), event.amount())
            .flatMap(result -> result.success()
                ? publishEvent("payment.completed", new PaymentCompletedEvent(event.orderId()))
                : publishEvent("payment.failed", new PaymentFailedEvent(event.orderId(), result.reason())))
            .subscribe();
    }
}
```

**When:** ≤4 services, simple flows, teams own their service end-to-end.

### Orchestration (Central Coordinator)

A saga orchestrator directs the workflow, calling services and handling compensation.

```java
@Component
@RequiredArgsConstructor
public class OrderSagaOrchestrator {
    private final PaymentClient paymentClient;
    private final InventoryClient inventoryClient;

    public Mono<OrderResult> executeSaga(CreateOrderCommand cmd) {
        return paymentClient.reservePayment(cmd.orderId(), cmd.amount())
            .flatMap(paymentResult -> inventoryClient.reserveStock(cmd.orderId(), cmd.items()))
            .onErrorResume(e -> compensate(cmd.orderId(), e));
    }

    private Mono<OrderResult> compensate(String orderId, Throwable error) {
        return paymentClient.cancelPayment(orderId)
            .then(Mono.just(OrderResult.failed(orderId, error.getMessage())));
    }
}
```

**When:** >4 services, complex flows with branching, need visibility into saga state.

## Transactional Outbox Pattern

Guarantees at-least-once event delivery by writing events to an outbox table in the same DB transaction as the business change.

```
[Business Logic + Outbox INSERT] --same TX--> [DB]
[Outbox Poller/CDC] --reads--> [Outbox Table] --publishes--> [Kafka/RabbitMQ]
```

### With Summer Framework

```java
// In business logic (same transaction)
return orderRepository.save(order)
    .flatMap(saved -> outboxService.saveEvent(
        "ORDER_CREATED", saved.getId(), mapper.writeValueAsString(saved)))
    .thenReturn(saved);
```

Summer's `OutboxService` handles scheduling, retry, and cleanup automatically. See **summer-data** skill.

### Manual Implementation (without Summer)

```java
@Transactional
public Mono<Order> createOrder(CreateOrderCommand cmd) {
    return orderRepository.save(Order.from(cmd))
        .flatMap(order -> outboxRepository.save(OutboxEvent.builder()
            .aggregateType("Order")
            .aggregateId(order.getId())
            .eventType("ORDER_CREATED")
            .payload(toJson(order))
            .status(OutboxStatus.PENDING)
            .build())
            .thenReturn(order));
}
```

## Event Sourcing Basics

Store state as a sequence of events rather than current state. Replay events to reconstruct state.

```java
public record OrderEvent(String orderId, String type, Instant timestamp, JsonNode data) {}

// Reconstruct aggregate from events
public Order reconstruct(List<OrderEvent> events) {
    Order order = Order.empty();
    for (OrderEvent event : events) {
        order = order.apply(event);
    }
    return order;
}
```

### When to Use Event Sourcing

| Use | Skip |
|-----|------|
| Full audit trail required | Simple CRUD |
| Complex domain with temporal queries | <3 entity types |
| Need to replay/rebuild state | Team unfamiliar with pattern |
| Regulatory compliance (finance, healthcare) | Low-volume, low-complexity |

## Event Schema Evolution

1. **Always backward compatible** — add optional fields, never remove/rename
2. **Schema Registry** — Avro/Protobuf with compatibility checks (Confluent Schema Registry)
3. **Versioned topics** — `order.created.v1`, `order.created.v2` for breaking changes
4. **Consumer tolerance** — ignore unknown fields, handle missing optional fields

## Idempotency

Every consumer must be idempotent. Strategies:

| Strategy | How | Best For |
|----------|-----|----------|
| **Dedup table** | Store processed event IDs in DB | Most reliable |
| **Natural idempotency** | `INSERT ... ON CONFLICT DO NOTHING` | DB operations |
| **Idempotency key** | Client-provided key in event header | API-driven |

```java
public Mono<Void> processEvent(IntegrationEvent event) {
    return processedEventRepository.existsById(event.eventId())
        .flatMap(exists -> exists
            ? Mono.empty()  // already processed
            : doProcess(event)
                .then(processedEventRepository.save(new ProcessedEvent(event.eventId()))));
}
```

## Anti-Patterns

| Anti-Pattern | Fix |
|---|---|
| Saga without compensation | Every step needs a rollback action |
| Event sourcing for simple CRUD | Use state-based persistence |
| No dead letter handling | Always configure DLT/DLQ |
| Synchronous saga steps | Use async messaging between steps |
| No idempotency in consumers | Dedup table or natural idempotency |
| Outbox without cleanup | Schedule periodic deletion of published events |
