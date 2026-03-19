# CQRS & Anti-Patterns Reference

Command/query separation, read models, CQRS package structure, and hexagonal anti-patterns.

## Table of Contents
- [CQRS Overview](#cqrs-overview)
- [Command Port & Use Case](#command-port--use-case)
- [Query Port & Use Case](#query-port--use-case)
- [Read Model](#read-model)
- [Query Adapter with DatabaseClient](#query-adapter-with-databaseclient)
- [CQRS Package Structure](#cqrs-package-structure)
- [Anti-Patterns](#anti-patterns)
- [Key Design Decisions](#key-design-decisions)

---

## CQRS Overview

Separate **command** (state changes, uses domain) from **query** (reads, can bypass domain).

```
Commands -> Application Service -> Domain Aggregate -> Write DB
Queries  -> Query Service        -> Read Model DAO   -> Read DB (or same DB)
```

Benefits: queries optimized for reading, commands enforce invariants, independent scaling.

---

## Command Port & Use Case

```java
public interface CreateOrderUseCase {
    Mono<OrderId> createOrder(CreateOrderCommand command);
}
public interface CancelOrderUseCase {
    Mono<Void> cancelOrder(CancelOrderCommand command);
}

public record CreateOrderCommand(String customerId, List<Item> items, Address shippingAddress) {
    public record Item(String productId, int quantity, BigDecimal price) {}
}
public record CancelOrderCommand(String orderId, String reason) {}
```

---

## Query Port & Use Case

```java
public interface OrderQueryUseCase {
    Mono<OrderSummary> findOrderById(String orderId);
    Flux<OrderSummary> findOrdersByCustomer(String customerId, int page, int size);
    Mono<OrderStatistics> getOrderStatistics(String customerId);
}

public record OrderSummary(String orderId, String customerId, String status,
    BigDecimal totalAmount, String currency, int itemCount, Instant createdAt) {}

public record OrderStatistics(long totalOrders, long confirmedOrders,
    BigDecimal totalSpent, Instant lastOrderDate) {}
```

---

## Read Model

Flat, denormalized view optimized for queries. Does NOT need to be an aggregate.

```java
@Table("order_summaries")
public class OrderSummaryEntity {
    @Id private String orderId;
    private String customerId;
    private String customerEmail;  // denormalized
    private String status;
    private BigDecimal totalAmount;
    private int itemCount;
    private Instant createdAt;
}

public interface OrderReadModelPort {
    Mono<OrderSummary> findById(String orderId);
    Flux<OrderSummary> findByCustomerId(String customerId, Pageable pageable);
}

@Service @RequiredArgsConstructor
public class OrderQueryService implements OrderQueryUseCase {
    private final OrderReadModelPort readModel;
    @Override
    public Mono<OrderSummary> findOrderById(String orderId) {
        return readModel.findById(orderId)
            .switchIfEmpty(Mono.error(new NotFoundException("Order not found: " + orderId)));
    }
}
```

---

## Query Adapter with DatabaseClient

```java
@Repository @RequiredArgsConstructor
public class OrderReadModelAdapter implements OrderReadModelPort {
    private final DatabaseClient db;

    @Override
    public Mono<OrderSummary> findById(String orderId) {
        return db.sql("""
                SELECT o.id, o.customer_id, o.status, o.total_amount, o.currency,
                       COUNT(oi.id) AS item_count, o.created_at
                FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.id
                WHERE o.id = :orderId GROUP BY o.id
                """)
            .bind("orderId", orderId)
            .map(row -> new OrderSummary(
                row.get("id", String.class), row.get("customer_id", String.class),
                row.get("status", String.class), row.get("total_amount", BigDecimal.class),
                row.get("currency", String.class), row.get("item_count", Integer.class),
                row.get("created_at", Instant.class)))
            .one();
    }
}
```

---

## CQRS Package Structure

```
com.example.order/
├── domain/
│   ├── model/         Order, Money (aggregates + VOs)
│   ├── event/         OrderCreatedEvent
│   ├── exception/     InvalidOrderException
│   └── port/
│       ├── in/        CreateOrderUseCase, OrderQueryUseCase
│       └── out/       OrderPersistencePort (write), OrderReadModelPort (read)
├── application/
│   ├── command/       CreateOrderService
│   ├── query/         OrderQueryService
│   └── dto/           CreateOrderCommand, OrderSummary
└── infrastructure/
    ├── rest/          OrderController (POST/PUT/DELETE), OrderQueryController (GET)
    ├── persistence/
    │   ├── write/     OrderR2dbcAdapter
    │   └── read/      OrderReadModelAdapter
    └── kafka/         OrderKafkaPublisher
```

---

## Anti-Patterns

### Anemic Domain Model

```java
// WRONG — data bag + service with all logic
public class Order { private String status; /* only getters/setters */ }
public class OrderService { public void confirm(Order o) { o.setStatus("CONFIRMED"); } }

// CORRECT — rich domain model
public class Order {
    public void confirm() {
        if (status != OrderStatus.CREATED) throw new InvalidOrderException("...");
        this.status = OrderStatus.CONFIRMED;
        registerEvent(new OrderConfirmedEvent(id));
    }
}
```

### Leaked Infrastructure to Domain

```java
// WRONG — domain imports Spring/JPA
@Entity public class Order { @Id private Long id; }

// CORRECT — domain is plain Java, JPA on infrastructure entity only
public class Order { private final OrderId id; }
@Entity public class OrderEntity { @Id private String id; }
```

### Use Case Doing Too Much

```java
// WRONG — handles HTTP, cache, email in use case
public class CreateOrderService {
    public void createOrder(HttpServletRequest req) { ... }
}

// CORRECT — orchestrates domain + ports only
public class CreateOrderService implements CreateOrderUseCase {
    public Mono<OrderId> createOrder(CreateOrderCommand cmd) {
        Order order = Order.create(...);
        return orderPersistence.save(order)
            .flatMap(saved -> eventPublisher.publishEvents(saved.getDomainEvents()));
    }
}
```

### Adapter Depending on Another Adapter

```java
// WRONG
public class OrderKafkaPublisher { private final OrderJpaRepository jpaRepo; }

// CORRECT — adapters only implement/use ports
public class OrderKafkaPublisher implements OrderEventPublisherPort {
    private final KafkaTemplate<String, Object> kafkaTemplate;
}
```

---

## Key Design Decisions

| Decision | Recommendation |
|---|---|
| Aggregates per transaction | One — coordinate via domain events |
| Read/write model | CQRS when queries differ from domain structure |
| Mapping layer | MapStruct (compile-time, no reflection) |
| Domain events timing | Register in domain, publish after persist |
| Port granularity | One input port per use case |
| Package organization | By feature first, then by layer within |
