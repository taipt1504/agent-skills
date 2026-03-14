# JPA / Hibernate — MySQL Best Practices

Spring Boot 3.x / Hibernate 6 / Java 17+

---

## Entity Design

```java
@Entity
@Table(
    name = "orders",
    indexes = {
        @Index(name = "idx_orders_user_id",  columnList = "user_id"),
        @Index(name = "idx_orders_status",   columnList = "status"),
        @Index(name = "idx_orders_created",  columnList = "created_at")
    }
)
@SQLRestriction("deleted_at IS NULL")   // Hibernate 6 — replaces deprecated @Where
@DynamicUpdate                           // Only UPDATE changed columns
@NoArgsConstructor(access = AccessLevel.PROTECTED)  // JPA requires no-arg; PROTECTED prevents misuse
@Getter
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)  // Maps to AUTO_INCREMENT
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)          // Match VARCHAR(20) in DDL
    private OrderStatus status;

    @Column(name = "total_amount", nullable = false, precision = 10, scale = 2)
    private BigDecimal totalAmount;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @OneToMany(mappedBy = "order", fetch = FetchType.LAZY,
               cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();

    // Static factory — never expose public constructor
    public static Order create(Long userId, BigDecimal totalAmount) {
        var order = new Order();
        order.userId = userId;
        order.totalAmount = totalAmount;
        order.status = OrderStatus.PENDING;
        order.createdAt = LocalDateTime.now();
        order.updatedAt = LocalDateTime.now();
        return order;
    }

    // Soft delete
    public void softDelete() {
        this.deletedAt = LocalDateTime.now();
    }
}
```

### Key Annotations

| Annotation | Purpose | Notes |
|------------|---------|-------|
| `@SQLRestriction(...)` | Hibernate 6 filter — replaces `@Where` | Applied to all JPQL/find queries automatically |
| `@DynamicUpdate` | UPDATE only changed columns | Reduces write amplification on wide tables |
| `@NoArgsConstructor(PROTECTED)` | Required by JPA; PROTECTED hides from app code | Pair with static factory method |
| `@GeneratedValue(IDENTITY)` | Maps to `AUTO_INCREMENT` | Do not use `SEQUENCE` — MySQL has no sequences |
| `@Enumerated(STRING)` | Store enum name as VARCHAR | Always pair with `@Column(length = 20)` |

---

## `@SQLRestriction` vs `@Where` (Hibernate 6)

```java
// ✅ Spring Boot 3.x / Hibernate 6+ — correct
@SQLRestriction("deleted_at IS NULL")
public class User { ... }

// ❌ Deprecated in Hibernate 6 — do not use
@Where(clause = "deleted_at IS NULL")
public class User { ... }
```

`@SQLRestriction` is applied automatically to all queries (JPQL, findById, Spring Data methods) except native queries. For native queries, add `WHERE deleted_at IS NULL` manually.

---

## N+1 Prevention

### When to Use Each Strategy

| Strategy | When | Trade-off |
|----------|------|-----------|
| `JOIN FETCH` in JPQL | Known association always needed | Cartesian product risk with multiple collections |
| `@EntityGraph` | Dynamic per-method selection | Cleaner than scattered JOIN FETCHes |
| `@BatchSize` | Large collections, rarely needed | Trades N+1 for N/batch queries |
| DTO projection | Read-only listing, no entity needed | Fastest — avoids entity load entirely |

```java
// ✅ JOIN FETCH — load association in single query
@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.orders WHERE u.status = :status")
List<User> findWithOrders(@Param("status") UserStatus status);

// ✅ EntityGraph — declare at method level (no JPQL needed)
@EntityGraph(attributePaths = {"orders", "orders.items"})
List<User> findByStatus(UserStatus status);

// ✅ BatchSize — IN clause batching (add to entity field)
@OneToMany(mappedBy = "user", fetch = FetchType.LAZY)
@BatchSize(size = 20)
private List<Order> orders;
```

### Multiple Collection JOIN FETCH — Use Separate Queries

```java
// ❌ Causes HibernateException: "cannot simultaneously fetch multiple bags"
@Query("SELECT u FROM User u LEFT JOIN FETCH u.orders LEFT JOIN FETCH u.addresses")

// ✅ Two separate queries + Hibernate first-level cache merges them
@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.orders WHERE u.id IN :ids")
List<User> findWithOrders(@Param("ids") List<Long> ids);

@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.addresses WHERE u.id IN :ids")
List<User> findWithAddresses(@Param("ids") List<Long> ids);
```

---

## Spring Data Specifications (Dynamic Queries)

```java
// Specification building blocks
public class OrderSpecifications {

    public static Specification<Order> hasUserId(Long userId) {
        return (root, query, cb) -> userId == null ? null
            : cb.equal(root.get("userId"), userId);
    }

    public static Specification<Order> hasStatus(OrderStatus status) {
        return (root, query, cb) -> status == null ? null
            : cb.equal(root.get("status"), status);
    }

    public static Specification<Order> createdAfter(LocalDateTime from) {
        return (root, query, cb) -> from == null ? null
            : cb.greaterThanOrEqualTo(root.get("createdAt"), from);
    }
}

// Repository: extend JpaSpecificationExecutor
public interface OrderRepository extends JpaRepository<Order, Long>,
                                         JpaSpecificationExecutor<Order> {}

// Service: compose at runtime
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

## Pagination Strategies

### Offset Pagination — Good for ≤10K rows

```java
// Repository
Page<Order> findByUserId(Long userId, Pageable pageable);

// Service
Page<Order> page = orderRepository.findByUserId(userId,
    PageRequest.of(pageNumber, 20, Sort.by("createdAt").descending()));
```

### Keyset (Cursor) Pagination — Required for Large Tables

`OFFSET N` forces MySQL to read and discard N rows. Keyset avoids this by anchoring on last-seen values.

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
    @Param("userId")  Long userId,
    @Param("cursor")  LocalDateTime cursor,
    @Param("lastId")  Long lastId,
    @Param("limit")   int limit
);
```

---

## Projections — Avoid Loading Full Entity for Reads

### Interface Projection (Lazy — only selected columns fetched)

```java
public interface OrderSummary {
    Long getId();
    String getStatus();
    BigDecimal getTotalAmount();
}

List<OrderSummary> findByUserId(Long userId);
```

### DTO Projection (Explicit — constructor expression in JPQL)

```java
public record OrderDto(Long id, OrderStatus status, BigDecimal totalAmount) {}

@Query("""
    SELECT new com.example.dto.OrderDto(o.id, o.status, o.totalAmount)
    FROM Order o WHERE o.userId = :userId
    """)
List<OrderDto> findOrderDtosByUserId(@Param("userId") Long userId);
```

**Trade-off**: Interface projections use Spring proxies and are simpler but slower for deep object graphs. DTO projections are faster and type-safe but require constructor maintenance.

---

## Batch Writes

```java
// ✅ saveAll() with rewriteBatchedStatements=true in HikariCP datasource props
// → sends one multi-row INSERT instead of N individual INSERTs
orderRepository.saveAll(orders);

// ✅ JdbcTemplate for high-volume batch (bypasses entity lifecycle hooks)
jdbcTemplate.batchUpdate(
    "INSERT INTO orders (user_id, status, total_amount) VALUES (?, ?, ?)",
    orders,
    100,   // batch size
    (ps, order) -> {
        ps.setLong(1, order.getUserId());
        ps.setString(2, order.getStatus().name());
        ps.setBigDecimal(3, order.getTotalAmount());
    }
);
```

> HikariCP must include `rewriteBatchedStatements=true` in `data-source-properties`
> for `saveAll()` batching to take effect — see [pool-transactions.md](pool-transactions.md).

---

## application.yml — JPA / Hibernate Config

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate          # Never use create/update in production
    properties:
      hibernate:
        dialect: org.hibernate.dialect.MySQLDialect
        default_batch_fetch_size: 20    # Applies @BatchSize globally
        jdbc:
          batch_size: 100              # Batch insert/update size
          order_inserts: true
          order_updates: true
        format_sql: false              # true only in dev
    open-in-view: false                # ALWAYS disable — prevents lazy-load trap
```
