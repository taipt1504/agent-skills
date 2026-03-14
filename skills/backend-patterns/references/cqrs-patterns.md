# CQRS Patterns Reference

Command/query separation, command/query buses, event sourcing, domain events, projections, separate read/write repositories.

## Table of Contents
- [CQRS Overview](#cqrs-overview)
- [Command Bus & Handlers](#command-bus--handlers)
- [Query Bus & Handlers](#query-bus--handlers)
- [Domain Events](#domain-events)
- [Event Sourcing (Lightweight)](#event-sourcing-lightweight)
- [Read Model Projections](#read-model-projections)
- [Separate Read/Write Repositories](#separate-readwrite-repositories)
- [Package Structure](#package-structure)

---

## CQRS Overview

```
Write Side                    Read Side
─────────                    ─────────
Command → CommandBus          Query → QueryBus
         → Handler                   → Handler
         → Aggregate                 → ReadModel
         → Event Store               (denormalized view)
         → Domain Event
         → Projection ──────────────→ ReadModel DB
```

**When to use CQRS:**
- Reads vastly outnumber writes (>10:1 ratio)
- Read/write data shapes differ significantly
- Independent scaling of reads and writes required
- Complex business logic on writes, simple queries on reads

---

## Command Bus & Handlers

```java
// Command sealed hierarchy
public sealed interface OrderCommand permits
    CreateOrderCommand, ConfirmOrderCommand, CancelOrderCommand, ShipOrderCommand {}

public record CreateOrderCommand(
    String idempotencyKey,
    String customerId,
    List<OrderItemCommand> items,
    AddressCommand shippingAddress
) implements OrderCommand {}

public record ConfirmOrderCommand(String orderId, String confirmedBy)
    implements OrderCommand {}
```

```java
// Command Handler port (interface)
public interface CommandHandler<C extends OrderCommand, R> {
    Mono<R> handle(C command);
}

// Command Bus
@Component @RequiredArgsConstructor
public class CommandBus {
    private final ApplicationContext context;

    @SuppressWarnings("unchecked")
    public <C extends OrderCommand, R> Mono<R> dispatch(C command) {
        Class<?> handlerClass = resolveHandlerClass(command.getClass());
        CommandHandler<C, R> handler = (CommandHandler<C, R>) context.getBean(handlerClass);
        return handler.handle(command);
    }

    private Class<?> resolveHandlerClass(Class<?> commandClass) {
        return HANDLER_MAP.get(commandClass);
    }

    private static final Map<Class<?>, Class<?>> HANDLER_MAP = Map.of(
        CreateOrderCommand.class, CreateOrderHandler.class,
        ConfirmOrderCommand.class, ConfirmOrderHandler.class,
        CancelOrderCommand.class, CancelOrderHandler.class
    );
}
```

```java
// Command Handler implementation
@Component @RequiredArgsConstructor @Slf4j
public class CreateOrderHandler implements CommandHandler<CreateOrderCommand, String> {

    private final OrderRepository orderRepository;
    private final DomainEventPublisher eventPublisher;

    @Override
    @Transactional
    public Mono<String> handle(CreateOrderCommand cmd) {
        // Check idempotency
        return orderRepository.existsByIdempotencyKey(cmd.idempotencyKey())
            .flatMap(exists -> {
                if (exists) {
                    return orderRepository.findIdByIdempotencyKey(cmd.idempotencyKey());
                }
                var order = Order.create(
                    CustomerId.of(cmd.customerId()),
                    toItems(cmd.items()),
                    toAddress(cmd.shippingAddress()),
                    cmd.idempotencyKey()
                );
                return orderRepository.save(order)
                    .flatMap(saved -> eventPublisher.publish(saved.domainEvents())
                        .thenReturn(saved.getId().value()));
            });
    }
}
```

---

## Query Bus & Handlers

```java
// Query sealed hierarchy
public sealed interface OrderQuery permits
    GetOrderByIdQuery, ListOrdersByCustomerQuery, GetOrderStatisticsQuery {}

public record GetOrderByIdQuery(String orderId) implements OrderQuery {}

public record ListOrdersByCustomerQuery(
    String customerId,
    OrderStatus status,
    String cursor,
    int limit
) implements OrderQuery {}
```

```java
// Query Handler
@Component @RequiredArgsConstructor
public class GetOrderByIdHandler implements QueryHandler<GetOrderByIdQuery, OrderSummary> {

    // ✅ Query uses READ model repository — not the aggregate repository
    private final OrderReadRepository readRepository;

    @Override
    public Mono<OrderSummary> handle(GetOrderByIdQuery query) {
        return readRepository.findSummaryById(query.orderId())
            .switchIfEmpty(Mono.error(new NotFoundException("Order not found: " + query.orderId())));
    }
}
```

---

## Domain Events

```java
// Event base
public interface DomainEvent {
    String aggregateId();
    Instant occurredAt();
    String eventType();
}

// Event records
public record OrderCreatedEvent(
    String aggregateId,
    String customerId,
    Money totalAmount,
    List<OrderItem> items,
    Instant occurredAt
) implements DomainEvent {
    public String eventType() { return "ORDER_CREATED"; }
}

public record OrderConfirmedEvent(
    String aggregateId,
    String confirmedBy,
    Instant occurredAt
) implements DomainEvent {
    public String eventType() { return "ORDER_CONFIRMED"; }
}
```

```java
// Domain Event Publisher (output port)
public interface DomainEventPublisher {
    Mono<Void> publish(List<DomainEvent> events);
}

// Kafka implementation
@Component @RequiredArgsConstructor
public class KafkaDomainEventPublisher implements DomainEventPublisher {
    private final KafkaTemplate<String, Object> kafkaTemplate;

    @Override
    public Mono<Void> publish(List<DomainEvent> events) {
        return Flux.fromIterable(events)
            .concatMap(event -> Mono.fromFuture(
                kafkaTemplate.send(topicFor(event), event.aggregateId(), event)))
            .then();
    }

    private String topicFor(DomainEvent event) {
        return "domain.orders." + event.eventType().toLowerCase().replace('_', '.');
    }
}
```

---

## Event Sourcing (Lightweight)

Store events instead of aggregate state; reconstruct from event stream.

```java
// Event store port
public interface EventStore {
    Mono<Void> append(String aggregateId, List<DomainEvent> events, long expectedVersion);
    Flux<DomainEvent> loadEvents(String aggregateId);
    Flux<DomainEvent> loadEvents(String aggregateId, long fromVersion);
}

// R2DBC event store
@Repository @RequiredArgsConstructor
public class R2dbcEventStore implements EventStore {
    private final DatabaseClient db;
    private final ObjectMapper objectMapper;

    @Override
    public Mono<Void> append(String aggregateId, List<DomainEvent> events, long expectedVersion) {
        return db.sql("""
                SELECT COUNT(*) FROM order_events WHERE aggregate_id = :id
                """)
            .bind("id", aggregateId)
            .mapValue(Long.class)
            .one()
            .flatMap(currentVersion -> {
                if (currentVersion != expectedVersion) {
                    return Mono.error(new OptimisticLockException(
                        "Concurrency conflict: expected %d, got %d"
                            .formatted(expectedVersion, currentVersion)));
                }
                return Flux.fromIterable(events)
                    .index()
                    .concatMap(indexed -> db.sql("""
                            INSERT INTO order_events
                            (aggregate_id, version, event_type, payload, occurred_at)
                            VALUES (:id, :version, :type, :payload::jsonb, :at)
                            """)
                        .bind("id", aggregateId)
                        .bind("version", expectedVersion + indexed.getT1() + 1)
                        .bind("type", indexed.getT2().eventType())
                        .bind("payload", serialize(indexed.getT2()))
                        .bind("at", indexed.getT2().occurredAt())
                        .then())
                    .then();
            });
    }

    @Override
    public Flux<DomainEvent> loadEvents(String aggregateId) {
        return db.sql("SELECT * FROM order_events WHERE aggregate_id = :id ORDER BY version")
            .bind("id", aggregateId)
            .map((row, meta) -> deserializeEvent(row))
            .all();
    }
}
```

```java
// Aggregate reconstruction from events
public class Order {
    public static Mono<Order> reconstitute(EventStore store, String id) {
        return store.loadEvents(id)
            .reduce(new Order(), Order::apply)
            .switchIfEmpty(Mono.error(new NotFoundException("Order not found: " + id)));
    }

    private Order apply(DomainEvent event) {
        return switch (event) {
            case OrderCreatedEvent e -> {
                this.id = OrderId.of(e.aggregateId());
                this.customerId = CustomerId.of(e.customerId());
                this.status = OrderStatus.PENDING;
                this.items = e.items();
                yield this;
            }
            case OrderConfirmedEvent e -> {
                this.status = OrderStatus.CONFIRMED;
                yield this;
            }
            default -> this;
        };
    }
}
```

---

## Read Model Projections

```java
// Projection handler — listens to domain events, updates read model
@Component @RequiredArgsConstructor @Slf4j
public class OrderProjection {

    private final OrderReadRepository readRepository;

    @KafkaListener(topics = "domain.orders.order.created")
    public Mono<Void> on(OrderCreatedEvent event) {
        var summary = new OrderSummaryEntity(
            event.aggregateId(),
            event.customerId(),
            OrderStatus.PENDING,
            event.totalAmount().amount(),
            event.occurredAt()
        );
        return readRepository.save(summary).then();
    }

    @KafkaListener(topics = "domain.orders.order.confirmed")
    public Mono<Void> on(OrderConfirmedEvent event) {
        return readRepository.updateStatus(event.aggregateId(), OrderStatus.CONFIRMED);
    }

    @KafkaListener(topics = "domain.orders.order.shipped")
    public Mono<Void> on(OrderShippedEvent event) {
        return readRepository.updateStatusAndTrackingNumber(
            event.aggregateId(), OrderStatus.SHIPPED, event.trackingNumber());
    }
}
```

---

## Separate Read/Write Repositories

```java
// Write-side repository (aggregate storage)
public interface OrderRepository {
    Mono<Order> findById(OrderId id);
    Mono<Order> save(Order order);
    Mono<Boolean> existsByIdempotencyKey(String key);
}

// Read-side repository (optimized for queries — denormalized views)
public interface OrderReadRepository {
    Mono<OrderSummary> findSummaryById(String orderId);
    Flux<OrderSummary> findByCustomer(String customerId, OrderStatus status, String cursor, int limit);
    Mono<OrderStatistics> getStatisticsByCustomer(String customerId);
}

// Read model entity — denormalized, no domain logic
@Table("order_summaries")  // updated by projections
public class OrderSummaryEntity {
    private String id;
    private String customerId;
    private String customerEmail;   // denormalized
    private String customerName;    // denormalized
    private OrderStatus status;
    private BigDecimal totalAmount;
    private int itemCount;          // pre-computed
    private Instant createdAt;
    private Instant updatedAt;
}
```

```java
// Query handler uses JOIN-optimized read model
@Component @RequiredArgsConstructor
public class ListOrdersHandler implements QueryHandler<ListOrdersByCustomerQuery, CursorPage<OrderSummary>> {

    private final DatabaseClient db;

    @Override
    public Mono<CursorPage<OrderSummary>> handle(ListOrdersByCustomerQuery query) {
        return db.sql("""
            SELECT os.*, u.email, u.name
            FROM order_summaries os
            JOIN users u ON u.id = os.customer_id
            WHERE os.customer_id = :customerId
              AND (:status IS NULL OR os.status = :status)
              AND (:cursor IS NULL OR (os.created_at, os.id) < (:cursorDate, :cursorId))
            ORDER BY os.created_at DESC, os.id DESC
            LIMIT :limit
            """)
            .bind("customerId", query.customerId())
            .bind("status", query.status() == null ? null : query.status().name())
            // ... bind cursor params
            .map(row -> mapToSummary(row))
            .all()
            .collectList()
            .map(items -> buildCursorPage(items, query.limit()));
    }
}
```
