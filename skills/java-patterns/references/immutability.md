# Immutability Patterns

## Table of Contents

- [Records (Java 14+)](#records-java-14)
- [Lombok @Value](#lombok-value)
- [Builder Pattern](#builder-pattern)
- [Defensive Copies](#defensive-copies)
- [Immutable Collections](#immutable-collections)

---

## Records (Java 14+)

Records are the preferred way to create immutable data carriers.

```java
// Simple record
public record UserId(String value) {
    public UserId {
        Objects.requireNonNull(value, "value must not be null");
        if (value.isBlank()) {
            throw new IllegalArgumentException("value must not be blank");
        }
    }
}

// Record with validation and derived fields
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount);
        Objects.requireNonNull(currency);
        if (amount.scale() > currency.getDefaultFractionDigits()) {
            throw new IllegalArgumentException("Invalid scale for currency");
        }
    }
    
    public Money add(Money other) {
        if (!this.currency.equals(other.currency)) {
            throw new IllegalArgumentException("Cannot add different currencies");
        }
        return new Money(amount.add(other.amount), currency);
    }
}

// Record with @Builder (Lombok)
@Builder
public record CreateUserCommand(
    @NonNull String name,
    @NonNull String email,
    @Builder.Default Instant createdAt = Instant.now(),
    @Builder.Default Set<String> roles = Set.of()
) {}
```

## Lombok @Value

For classes that need inheritance or complex logic:

```java
@Value
@Builder
public class UserProfile {
    @NonNull String id;
    @NonNull String name;
    String bio;  // nullable
    @Builder.Default
    List<String> interests = List.of();
    @Builder.Default
    Instant createdAt = Instant.now();
    
    // Custom method
    public boolean hasInterest(String interest) {
        return interests.contains(interest);
    }
}
```

## Builder Pattern

### With Lombok

```java
@Builder(toBuilder = true)  // toBuilder for "copy with modification"
public record Order(
    String id,
    String customerId,
    List<OrderItem> items,
    OrderStatus status,
    Instant createdAt
) {
    // Create modified copy
    public Order withStatus(OrderStatus newStatus) {
        return this.toBuilder().status(newStatus).build();
    }
}

// Usage
Order updated = order.toBuilder()
    .status(OrderStatus.COMPLETED)
    .build();
```

### Manual Builder (when Lombok not available)

```java
public record Config(
    String host,
    int port,
    Duration timeout,
    boolean enableSsl
) {
    public static Builder builder() {
        return new Builder();
    }
    
    public static class Builder {
        private String host = "localhost";
        private int port = 8080;
        private Duration timeout = Duration.ofSeconds(30);
        private boolean enableSsl = false;
        
        public Builder host(String host) { this.host = host; return this; }
        public Builder port(int port) { this.port = port; return this; }
        public Builder timeout(Duration timeout) { this.timeout = timeout; return this; }
        public Builder enableSsl(boolean enableSsl) { this.enableSsl = enableSsl; return this; }
        
        public Config build() {
            return new Config(host, port, timeout, enableSsl);
        }
    }
}
```

## Defensive Copies

Always copy mutable objects when receiving or returning:

```java
public record Order(String id, List<OrderItem> items) {
    // Compact constructor - defensive copy on input
    public Order {
        items = List.copyOf(items);  // Creates immutable copy
    }
}

// For mutable internal state
public class OrderService {
    private final List<Order> orders = new ArrayList<>();
    
    // ✅ Return defensive copy
    public List<Order> getOrders() {
        return List.copyOf(orders);
    }
    
    // ✅ Copy on input
    public void setOrders(List<Order> newOrders) {
        this.orders.clear();
        this.orders.addAll(newOrders);
    }
}
```

## Immutable Collections

### Creating Immutable Collections

```java
// ✅ Factory methods (Java 9+)
List<String> list = List.of("a", "b", "c");
Set<String> set = Set.of("a", "b", "c");
Map<String, Integer> map = Map.of("a", 1, "b", 2);

// ✅ From mutable collection
List<String> immutable = List.copyOf(mutableList);

// ✅ Collectors
List<String> collected = stream.collect(Collectors.toUnmodifiableList());
Set<String> collectedSet = stream.collect(Collectors.toUnmodifiableSet());
Map<K, V> collectedMap = stream.collect(
    Collectors.toUnmodifiableMap(Item::key, Item::value)
);
```

### When to Use Each

| Type                              | Use Case                                 |
|-----------------------------------|------------------------------------------|
| `List.of()`                       | Small, known elements at compile time    |
| `List.copyOf()`                   | Converting existing collection           |
| `Collections.unmodifiableList()`  | Wrapper (original can still be modified) |
| `Collectors.toUnmodifiableList()` | Stream terminal operation                |
