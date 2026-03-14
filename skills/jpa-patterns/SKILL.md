---
name: jpa-patterns
description: JPA/Hibernate patterns for Spring Data — entity design, N+1 prevention, HikariCP configuration, and pagination. For migrations see database-migrations skill.
---

# JPA/Hibernate Patterns

## When to Activate

- Writing or reviewing `@Entity` classes
- Configuring Spring Data JPA repositories
- Working with HikariCP connection pool settings
- Creating JPA entities and repository queries
- Debugging N+1 query problems
- Implementing pagination or DTO projections

## Entity Design

### Audit Fields

```java
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
@Getter
public abstract class BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @CreatedDate
    @Column(updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    @Version
    private Long version;
}
```

### Entity with Lombok Builder

```java
// GOOD: Immutable-style entity with builder
@Entity
@Table(name = "orders")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA requires no-arg
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(toBuilder = true)
public class Order extends BaseEntity {

    @Column(nullable = false)
    private String customerId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private OrderStatus status;

    @Column(nullable = false, precision = 19, scale = 2)
    private BigDecimal totalAmount;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<OrderItem> items = new ArrayList<>();

    // Domain method — not a setter
    public void addItem(OrderItem item) {
        items.add(item);
        item.setOrder(this);
    }
}
```

```java
// BAD: Mutable entity with public setters
@Entity
@Data  // Generates setters, equals/hashCode (problematic for entities)
public class Order {
    @Id @GeneratedValue
    private Long id;
    private String status; // Raw string instead of enum
    // Setters allow bypassing domain invariants
}
```

### Equals/HashCode for Entities

```java
// GOOD: Use business key or ID-based with null safety
@Override
public boolean equals(Object o) {
    if (this == o) return true;
    if (!(o instanceof Order other)) return false;
    return id != null && id.equals(other.getId());
}

@Override
public int hashCode() {
    return getClass().hashCode(); // Consistent across states
}
```

```java
// BAD: @Data or @EqualsAndHashCode on entities — breaks with proxies and detached state
```

## N+1 Query Prevention

### EntityGraph (Declarative)

```java
// GOOD: EntityGraph for predictable eager loading
public interface OrderRepository extends JpaRepository<Order, Long> {

    @EntityGraph(attributePaths = {"items", "items.product"})
    Optional<Order> findWithItemsById(Long id);

    @EntityGraph(attributePaths = {"customer"})
    List<Order> findByStatus(OrderStatus status);
}
```

### JOIN FETCH (JPQL)

```java
// GOOD: JOIN FETCH for complex queries
@Query("SELECT o FROM Order o " +
       "JOIN FETCH o.items i " +
       "JOIN FETCH i.product " +
       "WHERE o.customerId = :customerId AND o.status = :status")
List<Order> findOrdersWithDetails(
    @Param("customerId") String customerId,
    @Param("status") OrderStatus status
);
```

### DTO Projections (Best for Read-Only)

```java
// GOOD: DTO projection — no entity overhead, no N+1
public record OrderSummary(Long id, String customerId, BigDecimal totalAmount, long itemCount) {}

@Query("SELECT new com.example.dto.OrderSummary(o.id, o.customerId, o.totalAmount, COUNT(i)) " +
       "FROM Order o LEFT JOIN o.items i " +
       "WHERE o.status = :status " +
       "GROUP BY o.id, o.customerId, o.totalAmount")
Page<OrderSummary> findOrderSummaries(@Param("status") OrderStatus status, Pageable pageable);
```

```java
// BAD: Fetching full entities for read-only display
List<Order> orders = orderRepository.findAll(); // Loads ALL orders + triggers N+1 for items
orders.forEach(o -> System.out.println(o.getItems().size())); // N+1!
```

## HikariCP Configuration

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10          # connections = ((2 * cpu_cores) + disk_spindles)
      minimum-idle: 5                # Keep warm connections ready
      idle-timeout: 300000           # 5 min — release idle connections
      max-lifetime: 1800000          # 30 min — prevent stale connections
      connection-timeout: 30000      # 30s — fail fast on pool exhaustion
      leak-detection-threshold: 60000 # 60s — log warning for unreturned connections
      pool-name: MyApp-HikariPool
```

### Pool Sizing Formula

```
connections = ((2 * cpu_cores) + number_of_disks)
```

For a 4-core server with SSD: `(2 * 4) + 1 = 9` connections. Round to 10.

**Rule:** Smaller pools with a longer queue perform better than oversized pools. Start small, measure, then increase.

## Pagination

### Offset-Based (Standard)

```java
// Repository
Page<Order> findByStatus(OrderStatus status, Pageable pageable);

// Service
public Page<OrderDto> getOrders(OrderStatus status, int page, int size) {
    Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
    return orderRepository.findByStatus(status, pageable)
        .map(orderMapper::toDto);
}
```

### Cursor-Based (Large Datasets)

```java
// Repository — keyset pagination
@Query("SELECT o FROM Order o WHERE o.createdAt < :cursor ORDER BY o.createdAt DESC")
Slice<Order> findBeforeCursor(@Param("cursor") Instant cursor, Pageable pageable);

// Service
public Slice<OrderDto> getOrdersCursor(Instant cursor, int size) {
    Pageable pageable = PageRequest.of(0, size);
    return orderRepository.findBeforeCursor(
        cursor != null ? cursor : Instant.now(), pageable
    ).map(orderMapper::toDto);
}
```

**Use `Page<T>`** when total count is needed (UI pagination). **Use `Slice<T>`** when you only need "has next?" (infinite scroll) — avoids `COUNT(*)` query.

> For Flyway migration patterns, see the `database-migrations` skill.

## Verification Checklist

- [ ] No `@Data` on entities (use `@Getter` + `@NoArgsConstructor` + `@Builder`)
- [ ] `equals()`/`hashCode()` based on ID or business key, not `@Data`
- [ ] `@Version` for optimistic locking where needed
- [ ] `@EntityGraph` or `JOIN FETCH` for known N+1 paths
- [ ] DTO projections for read-only queries
- [ ] `@Transactional(readOnly = true)` on query methods
- [ ] HikariCP leak detection enabled in non-prod
- [ ] Pagination returns `Page<Dto>`, never `Page<Entity>`
