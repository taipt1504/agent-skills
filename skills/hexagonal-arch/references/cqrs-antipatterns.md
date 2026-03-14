# CQRS & Anti-Patterns Reference

Command/query separation, read models, CQRS package structure, and all hexagonal anti-patterns.

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
Commands → Application Service → Domain Aggregate → Write DB
Queries  → Query Service        → Read Model DAO   → Read DB (or same DB)
```

Benefits:
- Queries optimized for reading (no domain overhead)
- Commands enforce invariants through domain
- Independent scaling of read/write

---

## Command Port & Use Case

```java
// Input port — what the application can do
public interface CreateOrderUseCase {
    Mono<OrderId> createOrder(CreateOrderCommand command);
}

public interface CancelOrderUseCase {
    Mono<Void> cancelOrder(CancelOrderCommand command);
}

// Commands (immutable data carriers — no behavior)
public record CreateOrderCommand(
    String customerId,
    List<Item> items,
    Address shippingAddress
) {
    public record Item(String productId, int quantity, BigDecimal price) {}
}

public record CancelOrderCommand(String orderId, String reason) {}
```

---

## Query Port & Use Case

```java
// Query input port
public interface OrderQueryUseCase {
    Mono<OrderSummary> findOrderById(String orderId);
    Flux<OrderSummary> findOrdersByCustomer(String customerId, int page, int size);
    Mono<OrderStatistics> getOrderStatistics(String customerId);
}

// Query result (read model projection — optimized for API responses)
public record OrderSummary(
    String orderId,
    String customerId,
    String status,
    BigDecimal totalAmount,
    String currency,
    int itemCount,
    Instant createdAt
) {}

public record OrderStatistics(
    long totalOrders,
    long confirmedOrders,
    BigDecimal totalSpent,
    Instant lastOrderDate
) {}
```

---

## Read Model

The read model is a flat, denormalized view optimized for queries. Does NOT need to be an aggregate.

```java
// Read model entity (can be a DB view or denormalized table)
@Table("order_summaries")  // can be a materialized view
public class OrderSummaryEntity {
    @Id private String orderId;
    private String customerId;
    private String customerEmail;  // denormalized from customer
    private String status;
    private BigDecimal totalAmount;
    private String currency;
    private int itemCount;
    private String firstProductName;  // denormalized for display
    private Instant createdAt;
    private Instant updatedAt;
}

// Read model repository (output port for queries)
public interface OrderReadModelPort {
    Mono<OrderSummary> findById(String orderId);
    Flux<OrderSummary> findByCustomerId(String customerId, Pageable pageable);
    Mono<OrderStatistics> getStatisticsByCustomer(String customerId);
}

// Application service for queries
@Service @RequiredArgsConstructor
public class OrderQueryService implements OrderQueryUseCase {
    private final OrderReadModelPort readModel;  // NOT OrderPersistencePort

    @Override
    public Mono<OrderSummary> findOrderById(String orderId) {
        return readModel.findById(orderId)
            .switchIfEmpty(Mono.error(new NotFoundException("Order not found: " + orderId)));
    }

    @Override
    public Flux<OrderSummary> findOrdersByCustomer(String customerId, int page, int size) {
        return readModel.findByCustomerId(customerId, PageRequest.of(page, size));
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
                FROM orders o
                LEFT JOIN order_items oi ON oi.order_id = o.id
                WHERE o.id = :orderId
                GROUP BY o.id
                """)
            .bind("orderId", orderId)
            .map(row -> new OrderSummary(
                row.get("id", String.class),
                row.get("customer_id", String.class),
                row.get("status", String.class),
                row.get("total_amount", BigDecimal.class),
                row.get("currency", String.class),
                row.get("item_count", Integer.class),
                row.get("created_at", Instant.class)
            ))
            .one();
    }

    @Override
    public Flux<OrderSummary> findByCustomerId(String customerId, Pageable pageable) {
        return db.sql("""
                SELECT o.id, o.customer_id, o.status, o.total_amount, o.currency,
                       COUNT(oi.id) AS item_count, o.created_at
                FROM orders o
                LEFT JOIN order_items oi ON oi.order_id = o.id
                WHERE o.customer_id = :customerId
                GROUP BY o.id
                ORDER BY o.created_at DESC
                LIMIT :limit OFFSET :offset
                """)
            .bind("customerId", customerId)
            .bind("limit", pageable.getPageSize())
            .bind("offset", pageable.getOffset())
            .map(row -> /* map to OrderSummary */ null)
            .all();
    }

    @Override
    public Mono<OrderStatistics> getStatisticsByCustomer(String customerId) {
        return db.sql("""
                SELECT COUNT(*) AS total, SUM(total_amount) AS spent,
                       COUNT(CASE WHEN status = 'CONFIRMED' THEN 1 END) AS confirmed,
                       MAX(created_at) AS last_order
                FROM orders WHERE customer_id = :customerId
                """)
            .bind("customerId", customerId)
            .map(row -> new OrderStatistics(
                row.get("total", Long.class),
                row.get("confirmed", Long.class),
                row.get("spent", BigDecimal.class),
                row.get("last_order", Instant.class)
            ))
            .one();
    }
}
```

---

## CQRS Package Structure

```
com.example.order/
├── domain/
│   ├── model/         Order, OrderItem, Money (aggregates + VOs)
│   ├── event/         OrderCreatedEvent, OrderConfirmedEvent
│   ├── exception/     InvalidOrderException, NotFoundException
│   └── port/
│       ├── in/        CreateOrderUseCase, CancelOrderUseCase
│       │              OrderQueryUseCase
│       └── out/       OrderPersistencePort (write)
│                      OrderReadModelPort (read)
│                      PaymentPort, OrderEventPublisherPort
│
├── application/
│   ├── command/       CreateOrderService, CancelOrderService
│   ├── query/         OrderQueryService
│   └── dto/           CreateOrderCommand, OrderSummary, OrderStatistics
│
└── infrastructure/
    ├── rest/
    │   ├── OrderController (command endpoints → POST/PUT/DELETE)
    │   ├── OrderQueryController (query endpoints → GET)
    │   └── mapper/    OrderRestMapper
    ├── persistence/
    │   ├── write/     OrderR2dbcAdapter (implements OrderPersistencePort)
    │   └── read/      OrderReadModelAdapter (implements OrderReadModelPort)
    ├── kafka/         OrderKafkaPublisher
    └── payment/       PaymentApiAdapter
```

---

## Anti-Patterns

### Anemic Domain Model

```java
// ❌ WRONG — domain object is just a data bag
public class Order {
    private String id;
    private String status;
    // only getters/setters, no business logic
}

// Application service has all business logic
public class OrderService {
    public void confirm(Order order) {
        if (!order.getStatus().equals("CREATED")) throw new Exception(...);
        order.setStatus("CONFIRMED");  // ← business rule in service, not domain
    }
}

// ✅ CORRECT — domain object has business logic
public class Order {
    public void confirm() {
        if (status != OrderStatus.CREATED)
            throw new InvalidOrderException("Cannot confirm order in status: " + status);
        this.status = OrderStatus.CONFIRMED;
        registerEvent(new OrderConfirmedEvent(id, totalAmount));
    }
}
```

### Leaked Infrastructure to Domain

```java
// ❌ WRONG — domain imports Spring/JPA
import org.springframework.data.annotation.Id;
import javax.persistence.Entity;
@Entity public class Order { @Id private Long id; }

// ✅ CORRECT — domain is plain Java
public class Order { private final OrderId id; }
// JPA/R2DBC annotations only on infrastructure entities
@Entity public class OrderEntity { @Id private String id; }
```

### Use Case Doing Too Much

```java
// ❌ WRONG — use case handles HTTP, DB, cache, emails, logging
public class CreateOrderService {
    public void createOrder(HttpServletRequest httpReq) {  // HTTP concern in use case
        String json = httpReq.getBody();
        cacheService.invalidate(userId);  // cache concern in use case
        emailService.sendMail(email, subject, body);  // notification concern in use case
    }
}

// ✅ CORRECT — use case only orchestrates domain + ports
public class CreateOrderService implements CreateOrderUseCase {
    public Mono<OrderId> createOrder(CreateOrderCommand cmd) {
        Order order = Order.create(/* from cmd */);
        return orderPersistence.save(order)
            .flatMap(saved -> eventPublisher.publishEvents(saved.getDomainEvents()));
    }
}
```

### Adapter Depending on Another Adapter

```java
// ❌ WRONG — infrastructure adapters should not know each other
@Component
public class OrderKafkaPublisher {
    private final OrderJpaRepository jpaRepo;  // ← adapter depending on adapter
}

// ✅ CORRECT — adapters only implement/use ports
@Component
public class OrderKafkaPublisher implements OrderEventPublisherPort {
    private final KafkaTemplate<String, Object> kafkaTemplate;  // only external dependency
}
```

---

## Key Design Decisions

| Decision | Options | Recommendation |
|---|---|---|
| **One aggregate per transaction** | Single or multiple aggregates | Always one — coordinate via domain events |
| **Sharing read/write model** | Single model vs CQRS | CQRS when queries differ significantly from domain structure |
| **Mapping layer** | Manual, MapStruct, ModelMapper | MapStruct — compile-time safety, no reflection |
| **Domain events timing** | Before or after persist | Register in domain, publish after successful persist |
| **Port granularity** | One port per aggregate vs fine-grained | Fine-grained — one input port per use case (easier to test) |
| **Package by layer vs feature** | `domain/`, `app/`, `infra/` vs `order/`, `payment/` | Package by feature first, then by layer within each feature |
