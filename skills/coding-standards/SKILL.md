---
name: java-standards
description: Java 17+ coding standards — KISS/DRY/SOLID principles, records, sealed classes, pattern matching, naming conventions, immutability, error handling, reactive patterns, Optional/Stream best practices
---

# Java Standards & Best Practices

## When to Activate

- Writing or reviewing any Java code
- Refactoring existing code for readability or maintainability
- Code review sessions — apply as checklist
- Designing exception hierarchies, domain models, or reactive chains

---

## 1. Core Principles

| Principle | Rule |
|-----------|------|
| **Readability First** | Self-documenting names over comments; consistent formatting |
| **KISS** | Simplest solution that works; avoid clever code |
| **DRY** | Extract repeated logic; no copy-paste |
| **YAGNI** | No speculative features; add complexity only when required |
| **Single Responsibility** | One class/method = one purpose |

---

## 2. Java 17+ Features

### Records
Use for immutable data carriers: DTOs, value objects, events, query results. Not for JPA entities, Spring beans, or classes requiring inheritance.

```java
// GOOD: DTO record
public record OrderResponse(Long id, String customerId, BigDecimal totalAmount, OrderStatus status) {}

// GOOD: Compact constructor validation
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount, "amount must not be null");
        if (amount.compareTo(BigDecimal.ZERO) < 0) throw new IllegalArgumentException("amount must be non-negative");
    }
}

// BAD: @Value class when record suffices
@Value public class OrderResponse { Long id; String customerId; }
```

### Sealed Classes
Use for exhaustive type hierarchies — domain events, result types.

```java
public sealed interface DomainEvent permits OrderCreatedEvent, OrderShippedEvent, OrderCancelledEvent {
    Instant occurredAt();
    String aggregateId();
}

public record OrderCreatedEvent(String aggregateId, Instant occurredAt, String customerId, BigDecimal amount) implements DomainEvent {}
public record OrderCancelledEvent(String aggregateId, Instant occurredAt, String reason) implements DomainEvent {}
```

### Pattern Matching instanceof

```java
// GOOD
if (event instanceof OrderCreatedEvent created) {
    processNewOrder(created.customerId(), created.amount());
}

// BAD
if (event instanceof OrderCreatedEvent) {
    OrderCreatedEvent created = (OrderCreatedEvent) event; // explicit cast
}
```

### Text Blocks

```java
// GOOD
String query = """
    SELECT o.id, o.customer_id FROM orders o
    WHERE o.status = :status AND o.created_at > :since
    ORDER BY o.created_at DESC
    """;

// BAD: concatenated strings
String query = "SELECT o.id " + "FROM orders o " + "WHERE o.status = :status";
```

---

## 3. Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Class | PascalCase | `OrderService`, `PaymentGateway` |
| Method | camelCase, verb-first | `createOrder()`, `findByEmail()` |
| Variable | descriptive noun | `marketSearchQuery`, `isUserAuthenticated` |
| Constant | UPPER_SNAKE_CASE | `MAX_RETRY_ATTEMPTS`, `DEFAULT_PAGE_SIZE` |
| Package | lowercase | `com.example.order.domain` |
| Test method | shouldDoXWhenY | `shouldReturnOrderWhenIdExists()` |
| Boolean | is/has/can prefix | `isActive()`, `hasPermission()` |
| Record | Noun, no "Dto" suffix for internal | `OrderResponse`, `Money` |
| Enum value | UPPER_SNAKE_CASE | `OrderStatus.IN_PROGRESS` |
| Exception | Descriptive + suffix | `MarketNotFoundException`, `InsufficientStockException` |

---

## 4. Immutability (Critical)

```java
// ✅ Immutable record with @Builder + @With
@Builder(toBuilder = true) @With
public record Order(String id, String customerId, OrderStatus status, BigDecimal total) {}

// Update = new instance
Order shipped = order.withStatus(OrderStatus.SHIPPED);

// ❌ Mutation inside reactive chain
market.setStatus(MarketStatus.ACTIVE); // WRONG

// ✅ Transform, don't mutate
return marketRepository.findById(id)
    .map(m -> m.withStatus(MarketStatus.ACTIVE))
    .flatMap(marketRepository::save);
```

---

## 5. Optional Usage Rules

```java
// DO: Return Optional from methods; chain operations
public Optional<Order> findByTrackingNumber(String trackingNumber) { ... }

public String getCustomerEmail(Long orderId) {
    return orderRepository.findById(orderId)
        .map(Order::getCustomerId)
        .flatMap(customerRepository::findById)
        .map(Customer::getEmail)
        .orElseThrow(() -> new OrderNotFoundException(orderId));
}

// DON'T: Optional as parameter, field, or collection element
public void createOrder(Optional<String> couponCode) { }  // BAD — use @Nullable or overload
private Optional<Address> shippingAddress;                // BAD — use nullable field + accessor
List<Optional<Order>> orders;                             // BAD — filter nulls instead
```

---

## 6. Stream Best Practices

```java
// GOOD: Readable chain; immutable result
var activeOrderTotals = orders.stream()
    .filter(order -> order.getStatus() == OrderStatus.ACTIVE)
    .map(Order::getTotalAmount)
    .reduce(BigDecimal.ZERO, BigDecimal::add);

var names = users.stream()
    .map(User::getFullName)
    .collect(Collectors.toUnmodifiableList());

// BAD: Side effects in streams
orders.stream().forEach(order -> {
    order.setStatus(CANCELLED); // mutation — wrong
    orderRepository.save(order);
});

// BAD: Overly complex stream — prefer a for-loop when readability suffers
```

---

## 7. Error Handling & Exception Hierarchy

```java
// Base domain exception with error code
public abstract class DomainException extends RuntimeException {
    private final String errorCode;
    protected DomainException(String errorCode, String message) { super(message); this.errorCode = errorCode; }
    public String getErrorCode() { return errorCode; }
}

// Specific domain exceptions
public class OrderNotFoundException extends DomainException {
    public OrderNotFoundException(Long id) { super("ORDER_NOT_FOUND", "Order not found: " + id); }
}

public class InsufficientStockException extends DomainException {
    public InsufficientStockException(String productId, int requested, int available) {
        super("INSUFFICIENT_STOCK", "Product %s: requested %d, available %d".formatted(productId, requested, available));
    }
}

// BAD: Generic exceptions — no error code, not catchable specifically
throw new RuntimeException("Order not found");
```

### Reactive Error Handling

```java
public Mono<Market> getMarket(String id) {
    return marketRepository.findById(id)
        .switchIfEmpty(Mono.error(new MarketNotFoundException(id)))
        .onErrorMap(DataAccessException.class, e -> new DatabaseException("DB error", e))
        .doOnError(e -> log.error("Error fetching market {}: {}", id, e.getMessage()));
}

// Fallback pattern
.onErrorResume(RedisException.class, e -> {
    log.warn("Redis unavailable, falling back to DB");
    return marketRepository.searchByName(query);
})
```

### Reactive Parallel Execution

```java
// ✅ Use Mono.zip for independent calls
return Mono.zip(
    userService.findById(userId),
    marketService.findByUser(userId).collectList(),
    statsService.getForUser(userId)
).map(t -> new DashboardData(t.getT1(), t.getT2(), t.getT3()));

// ❌ Unnecessary sequential nesting when calls are independent
```

---

## 8. Code Smells (Fix These)

| Smell | Rule | Fix |
|-------|------|-----|
| **Long Method** | > 30 lines | Extract named private methods |
| **Deep Nesting** | > 3 levels | Early return / guard clauses |
| **Magic Numbers** | `if (count > 3)` | `private static final int MAX_RETRIES = 3` |
| **God Class** | Service doing payments + notifications + reports | One class, one purpose |
| **N+1 Queries** | `flatMap(m -> repo.findByMarketId(m.id()))` | Batch fetch with `findByMarketIdIn(ids)` |

```java
// Guard clauses > deep nesting
if (user == null) return Mono.error(new UnauthorizedException());
if (!user.isAdmin()) return Mono.error(new ForbiddenException());
// Do the work
```

---

## 9. Verification Checklist

- [ ] Methods < 30 lines, classes < 400 lines, nesting depth < 4
- [ ] Records used for DTOs and value objects (not Lombok `@Value`)
- [ ] Sealed interfaces for exhaustive type hierarchies
- [ ] Pattern matching `instanceof` (no explicit casts after instanceof)
- [ ] Text blocks for multi-line strings
- [ ] Optional only as return type — never as field or parameter
- [ ] No mutable state or side effects in reactive chains / streams
- [ ] Domain exceptions with error codes (not generic `RuntimeException`)
- [ ] No hardcoded magic values — use constants or config
- [ ] `@Valid` on all `@RequestBody` parameters
- [ ] No empty catch blocks; no sensitive data in logs
- [ ] Tests written for all new code
