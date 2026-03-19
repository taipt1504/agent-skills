# JPA / Hibernate Patterns

Spring Boot 3.x / Hibernate 6 / Java 17+

---

## Entity Design

### Base Entity with Audit Fields

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

### Entity with Builder Pattern

```java
@Entity
@Table(name = "orders")
@SQLRestriction("deleted_at IS NULL")
@DynamicUpdate
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder(toBuilder = true)
@Getter
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

    public void addItem(OrderItem item) {
        items.add(item);
        item.setOrder(this);
    }
}
```

### Equals/HashCode for Entities

```java
// Use ID-based with null safety -- NOT @Data
@Override
public boolean equals(Object o) {
    if (this == o) return true;
    if (!(o instanceof Order other)) return false;
    return id != null && id.equals(other.getId());
}

@Override
public int hashCode() {
    return getClass().hashCode(); // Consistent across managed/detached states
}
```

### Key Annotations

| Annotation | Purpose | Notes |
|------------|---------|-------|
| `@SQLRestriction(...)` | Hibernate 6 soft delete filter | Replaces deprecated `@Where` |
| `@DynamicUpdate` | UPDATE only changed columns | Reduces write amplification |
| `@NoArgsConstructor(PROTECTED)` | JPA requires no-arg | Pair with static factory |
| `@Version` | Optimistic locking | Auto-incremented on save |

### PostgreSQL vs MySQL ID Strategy

```java
// PostgreSQL -- SEQUENCE strategy (enables batch inserts)
@Id
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "orders_id_seq")
@SequenceGenerator(name = "orders_id_seq", sequenceName = "orders_id_seq", allocationSize = 50)
private Long id;

// MySQL -- IDENTITY strategy (maps to AUTO_INCREMENT)
@Id
@GeneratedValue(strategy = GenerationType.IDENTITY)
private Long id;
```

---

## N+1 Query Prevention

### EntityGraph (Declarative)

```java
public interface OrderRepository extends JpaRepository<Order, Long> {

    @EntityGraph(attributePaths = {"items", "items.product"})
    Optional<Order> findWithItemsById(Long id);

    @EntityGraph(attributePaths = {"customer"})
    List<Order> findByStatus(OrderStatus status);
}
```

### JOIN FETCH (JPQL)

```java
@Query("SELECT o FROM Order o " +
       "JOIN FETCH o.items i " +
       "JOIN FETCH i.product " +
       "WHERE o.customerId = :customerId AND o.status = :status")
List<Order> findOrdersWithDetails(
    @Param("customerId") String customerId,
    @Param("status") OrderStatus status
);
```

### BatchSize (Lazy IN-Clause Batching)

```java
@OneToMany(mappedBy = "user", fetch = FetchType.LAZY)
@BatchSize(size = 20)
private List<Order> orders;
```

### Multiple Collections -- Separate Queries

```java
// Cannot JOIN FETCH two bags simultaneously
// Use separate queries; Hibernate L1 cache deduplicates

@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.orders WHERE u.id IN :ids")
List<User> findWithOrders(@Param("ids") List<Long> ids);

@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.addresses WHERE u.id IN :ids")
List<User> findWithAddresses(@Param("ids") List<Long> ids);
```

### DTO Projections (Best for Read-Only)

```java
public record OrderSummary(Long id, String customerId, BigDecimal totalAmount, long itemCount) {}

@Query("SELECT new com.example.dto.OrderSummary(o.id, o.customerId, o.totalAmount, COUNT(i)) " +
       "FROM Order o LEFT JOIN o.items i " +
       "WHERE o.status = :status " +
       "GROUP BY o.id, o.customerId, o.totalAmount")
Page<OrderSummary> findOrderSummaries(@Param("status") OrderStatus status, Pageable pageable);
```

### Interface Projection

```java
public interface OrderSummary {
    Long getId();
    String getStatus();
    BigDecimal getTotalAmount();
}

List<OrderSummary> findByUserId(Long userId);
```

---

## HikariCP Configuration

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      idle-timeout: 300000
      max-lifetime: 1800000
      connection-timeout: 30000
      leak-detection-threshold: 60000
      pool-name: MyApp-HikariPool
```

### Pool Sizing Formula

```
connections = (2 * cpu_cores) + number_of_disks
```

4-core server with SSD: `(2 * 4) + 1 = 9`. Round to 10.

Smaller pools with longer queues outperform oversized pools.

---

## Pagination

### Offset-Based (Standard)

```java
Page<Order> findByStatus(OrderStatus status, Pageable pageable);

public Page<OrderDto> getOrders(OrderStatus status, int page, int size) {
    Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
    return orderRepository.findByStatus(status, pageable).map(orderMapper::toDto);
}
```

Use `Page<T>` when total count needed (UI pagination).
Use `Slice<T>` when only "has next?" needed (infinite scroll) -- avoids `COUNT(*)`.

### Cursor-Based (Large Datasets)

```java
@Query("""
    SELECT o FROM Order o
    WHERE o.userId = :userId
      AND (o.createdAt < :cursor
           OR (o.createdAt = :cursor AND o.id < :lastId))
    ORDER BY o.createdAt DESC, o.id DESC
    LIMIT :limit
    """)
List<Order> findPageAfterCursor(
    @Param("userId") Long userId,
    @Param("cursor") Instant cursor,
    @Param("lastId") Long lastId,
    @Param("limit")  int limit
);
```

---

## Batch Writes

```java
// saveAll() -- effective with SEQUENCE strategy + batch_size configured
orderRepository.saveAll(orders);

// JdbcTemplate for high-volume (bypasses entity lifecycle)
jdbcTemplate.batchUpdate(
    "INSERT INTO orders (user_id, status, total_amount, created_at) VALUES (?, ?, ?, now())",
    orders,
    100,
    (ps, order) -> {
        ps.setLong(1, order.getUserId());
        ps.setString(2, order.getStatus());
        ps.setBigDecimal(3, order.getTotalAmount());
    }
);
```

Batch inserts require `SEQUENCE` strategy (PG) or `rewriteBatchedStatements=true` (MySQL).
`IDENTITY` strategy disables batch inserts in Hibernate.

---

## Spring Data Specifications (Dynamic Queries)

```java
public class OrderSpecifications {

    public static Specification<Order> hasUserId(Long userId) {
        return (root, query, cb) -> userId == null ? null
            : cb.equal(root.get("userId"), userId);
    }

    public static Specification<Order> hasStatus(String status) {
        return (root, query, cb) -> status == null ? null
            : cb.equal(root.get("status"), status);
    }

    public static Specification<Order> createdAfter(Instant from) {
        return (root, query, cb) -> from == null ? null
            : cb.greaterThanOrEqualTo(root.get("createdAt"), from);
    }
}

// Repository
public interface OrderRepository extends JpaRepository<Order, Long>,
                                         JpaSpecificationExecutor<Order> {}

// Service
public Page<Order> search(OrderSearchRequest req, Pageable pageable) {
    return orderRepository.findAll(
        where(hasUserId(req.userId()))
            .and(hasStatus(req.status()))
            .and(createdAfter(req.from())),
        pageable
    );
}
```

---

## Service Transaction Pattern

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class OrderService {

    private final OrderRepository orderRepository;

    public Optional<Order> findById(Long id) {
        return orderRepository.findById(id);
    }

    @Transactional
    public Order create(CreateOrderCommand cmd) {
        return orderRepository.save(Order.create(cmd));
    }
}
```

---

## Verification Checklist

- [ ] No `@Data` on entities (use `@Getter` + `@NoArgsConstructor` + `@Builder`)
- [ ] `equals()`/`hashCode()` based on ID or business key
- [ ] `@Version` for optimistic locking where needed
- [ ] `@EntityGraph` or `JOIN FETCH` for known N+1 paths
- [ ] DTO projections for read-only queries
- [ ] `@Transactional(readOnly = true)` on query methods
- [ ] HikariCP leak detection enabled in non-prod
- [ ] Pagination returns `Page<Dto>`, never `Page<Entity>`
