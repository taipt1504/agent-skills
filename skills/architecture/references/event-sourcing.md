# Event Sourcing — Reference

## Core Concept

Instead of storing current state, store every state change as an immutable event. Reconstruct state by replaying events.

```
Traditional: [Current State in DB Row]
Event Sourced: [Event1] → [Event2] → [Event3] → ... → [Current State]
```

## Event Store Design

### DDL (PostgreSQL)

```sql
CREATE TABLE event_store (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    aggregate_type  VARCHAR(100) NOT NULL,
    aggregate_id    VARCHAR(50) NOT NULL,
    event_type      VARCHAR(100) NOT NULL,
    event_data      JSONB NOT NULL,
    metadata        JSONB DEFAULT '{}',
    version         INT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (aggregate_type, aggregate_id, version)
);

CREATE INDEX idx_event_store_aggregate
    ON event_store (aggregate_type, aggregate_id, version);
```

### Event Record

```java
public record StoredEvent(
    Long id,
    String aggregateType,
    String aggregateId,
    String eventType,
    JsonNode eventData,
    JsonNode metadata,
    int version,
    Instant createdAt
) {}
```

## Aggregate Root with Events

```java
public abstract class EventSourcedAggregate {
    private final List<DomainEvent> uncommittedEvents = new ArrayList<>();
    private int version = 0;

    protected void applyChange(DomainEvent event) {
        apply(event);
        uncommittedEvents.add(event);
        version++;
    }

    protected abstract void apply(DomainEvent event);

    public List<DomainEvent> getUncommittedEvents() {
        return Collections.unmodifiableList(uncommittedEvents);
    }

    public void markCommitted() {
        uncommittedEvents.clear();
    }

    // Reconstruct from history
    public static <T extends EventSourcedAggregate> T reconstitute(
            Supplier<T> factory, List<DomainEvent> history) {
        T aggregate = factory.get();
        history.forEach(event -> {
            aggregate.apply(event);
            aggregate.version++;
        });
        return aggregate;
    }
}
```

### Order Aggregate Example

```java
public class Order extends EventSourcedAggregate {
    private String orderId;
    private OrderStatus status;
    private Money totalAmount;
    private List<OrderLine> lines = new ArrayList<>();

    public static Order create(String orderId, List<OrderLine> lines, Money total) {
        Order order = new Order();
        order.applyChange(new OrderCreatedEvent(orderId, lines, total));
        return order;
    }

    public void confirm() {
        if (status != OrderStatus.PENDING) {
            throw OrderExceptions.INVALID_STATUS_TRANSITION.toException();
        }
        applyChange(new OrderConfirmedEvent(orderId));
    }

    public void cancel(String reason) {
        if (status == OrderStatus.CANCELLED) return; // idempotent
        applyChange(new OrderCancelledEvent(orderId, reason));
    }

    @Override
    protected void apply(DomainEvent event) {
        switch (event) {
            case OrderCreatedEvent e -> {
                this.orderId = e.orderId();
                this.lines = e.lines();
                this.totalAmount = e.totalAmount();
                this.status = OrderStatus.PENDING;
            }
            case OrderConfirmedEvent e -> this.status = OrderStatus.CONFIRMED;
            case OrderCancelledEvent e -> this.status = OrderStatus.CANCELLED;
            default -> throw new IllegalArgumentException("Unknown event: " + event.getClass());
        }
    }
}
```

## Event Store Repository (R2DBC)

```java
@Repository
@RequiredArgsConstructor
public class R2dbcEventStore implements EventStore {
    private final DatabaseClient databaseClient;
    private final ObjectMapper mapper;

    public Mono<Void> saveEvents(String aggregateType, String aggregateId,
                                  List<DomainEvent> events, int expectedVersion) {
        return Flux.fromIterable(events)
            .index()
            .concatMap(indexed -> {
                int version = expectedVersion + indexed.getT1().intValue() + 1;
                DomainEvent event = indexed.getT2();
                return databaseClient.sql("""
                    INSERT INTO event_store (aggregate_type, aggregate_id, event_type, event_data, version)
                    VALUES (:type, :id, :eventType, :data::jsonb, :version)
                    """)
                    .bind("type", aggregateType)
                    .bind("id", aggregateId)
                    .bind("eventType", event.getClass().getSimpleName())
                    .bind("data", toJson(event))
                    .bind("version", version)
                    .fetch().rowsUpdated();
            })
            .then();
    }

    public Flux<StoredEvent> loadEvents(String aggregateType, String aggregateId) {
        return databaseClient.sql("""
            SELECT * FROM event_store
            WHERE aggregate_type = :type AND aggregate_id = :id
            ORDER BY version ASC
            """)
            .bind("type", aggregateType)
            .bind("id", aggregateId)
            .map(this::mapRow)
            .all();
    }
}
```

## Snapshots (Performance Optimization)

For aggregates with many events, periodically save a snapshot to avoid replaying full history.

```java
public Mono<Order> loadOrder(String orderId) {
    return snapshotStore.loadLatest("Order", orderId)
        .flatMap(snapshot -> eventStore
            .loadEventsAfter("Order", orderId, snapshot.version())
            .collectList()
            .map(events -> {
                Order order = deserialize(snapshot);
                events.forEach(e -> order.apply(deserializeEvent(e)));
                return order;
            }))
        .switchIfEmpty(Mono.defer(() -> eventStore
            .loadEvents("Order", orderId)
            .collectList()
            .map(events -> Order.reconstitute(Order::new, deserializeAll(events)))));
}
```

**Snapshot frequency:** Every N events (e.g., 50) or on schedule.

## Projections (Read Models)

Event sourcing separates write model (events) from read model (projections). Projections consume events and build query-optimized views.

```java
@Component
@RequiredArgsConstructor
public class OrderSummaryProjection {
    private final OrderSummaryRepository summaryRepo;

    @KafkaListener(topics = "order.events")
    public void onEvent(StoredEvent event) {
        switch (event.eventType()) {
            case "OrderCreatedEvent" -> summaryRepo.save(
                new OrderSummary(event.aggregateId(), "PENDING",
                    extractAmount(event), event.createdAt()));
            case "OrderConfirmedEvent" -> summaryRepo.updateStatus(
                event.aggregateId(), "CONFIRMED");
            case "OrderCancelledEvent" -> summaryRepo.updateStatus(
                event.aggregateId(), "CANCELLED");
        }
    }
}
```

## Decision Matrix

| Criteria | Event Sourcing | State-Based |
|----------|---------------|-------------|
| Audit trail | Complete, immutable | Manual audit table |
| Temporal queries | Native ("state at time T") | Complex/impossible |
| Complexity | Higher | Lower |
| Team experience | Requires ES knowledge | Standard CRUD |
| Storage | Grows with events | Fixed per entity |
| Read performance | Needs projections | Direct queries |
| Debugging | Replay events to reproduce | Inspect current state |

## Anti-Patterns

| Anti-Pattern | Fix |
|---|---|
| Mutable events | Events are IMMUTABLE — never update event_store rows |
| No snapshots on large aggregates | Snapshot every N events |
| Projection coupled to write model | Separate processes, eventual consistency |
| Missing idempotency in projections | Track last processed event ID |
| Using event sourcing for simple CRUD | Use state-based persistence |
| No schema evolution strategy | Version events, use backward-compatible changes |
