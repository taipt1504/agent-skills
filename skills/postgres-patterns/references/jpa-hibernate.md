# JPA / Hibernate — PostgreSQL Best Practices

Spring Boot 3.x / Hibernate 6 / Java 17+

---

## application.yml — JPA / Hibernate Config

```yaml
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME}?sslmode=require
    username: ${DB_USER}
    password: ${DB_PASS}
    driver-class-name: org.postgresql.Driver
  jpa:
    hibernate:
      ddl-auto: validate            # Never use create/update in production
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
        default_batch_fetch_size: 20    # Global @BatchSize fallback
        jdbc:
          batch_size: 100
          order_inserts: true
          order_updates: true
        format_sql: false               # true only in dev
    open-in-view: false                 # ALWAYS disable — prevents lazy-load across HTTP boundary
```

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
@DynamicUpdate                           // UPDATE only changed columns
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Getter
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "orders_id_seq")
    @SequenceGenerator(name = "orders_id_seq", sequenceName = "orders_id_seq", allocationSize = 50)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(nullable = false, length = 20)
    private String status;

    @Column(name = "total_amount", nullable = false, precision = 10, scale = 2)
    private BigDecimal totalAmount;

    @Column(columnDefinition = "text")
    private String note;

    @Type(JsonType.class)                // hypersistence-utils for JSONB
    @Column(columnDefinition = "jsonb")
    private Map<String, Object> metadata = new HashMap<>();

    @Column(name = "created_at", nullable = false, updatable = false,
            columnDefinition = "timestamptz")
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", columnDefinition = "timestamptz")
    private OffsetDateTime updatedAt;

    @Column(name = "deleted_at", columnDefinition = "timestamptz")
    private OffsetDateTime deletedAt;

    @OneToMany(mappedBy = "order", fetch = FetchType.LAZY,
               cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();

    public static Order create(Long userId, BigDecimal totalAmount) {
        var order = new Order();
        order.userId      = userId;
        order.totalAmount = totalAmount;
        order.status      = "PENDING";
        order.createdAt   = OffsetDateTime.now(ZoneOffset.UTC);
        order.updatedAt   = OffsetDateTime.now(ZoneOffset.UTC);
        return order;
    }

    public void softDelete() {
        this.deletedAt = OffsetDateTime.now(ZoneOffset.UTC);
    }
}
```

### Key Annotations for PostgreSQL

| Annotation | Purpose | Notes |
|------------|---------|-------|
| `@SQLRestriction(...)` | Hibernate 6 filter for soft deletes | Replaces deprecated `@Where`; applied to all JPQL/find queries |
| `@DynamicUpdate` | UPDATE only changed columns | Reduces write amplification on wide tables |
| `@NoArgsConstructor(PROTECTED)` | JPA no-arg + prevent public misuse | Use static factory for construction |
| `@GeneratedValue(SEQUENCE)` | Maps to PostgreSQL sequence | **Not IDENTITY** — PostgreSQL has no `AUTO_INCREMENT` |
| `@SequenceGenerator(allocationSize=50)` | Batch sequence allocation | Fetches 50 IDs per round-trip instead of 1; coordinate with DDL |
| `@Column(columnDefinition = "timestamptz")` | Forces `timestamptz` in schema | Hibernate defaults to `timestamp` — always override for PostgreSQL |

---

## `SEQUENCE` vs `IDENTITY` Strategy — PostgreSQL

```java
// ✅ PostgreSQL — SEQUENCE strategy (correct)
@Id
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "orders_id_seq")
@SequenceGenerator(name = "orders_id_seq", sequenceName = "orders_id_seq", allocationSize = 50)
private Long id;

// ❌ IDENTITY strategy — works but disables batch inserts in Hibernate
// PostgreSQL's GENERATED ALWAYS AS IDENTITY is still a sequence under the hood,
// but Hibernate's IDENTITY strategy fetches each ID after insert → breaks batch mode
@GeneratedValue(strategy = GenerationType.IDENTITY)
private Long id;
```

The DDL sequence must match `allocationSize`:

```sql
-- allocationSize = 50 → INCREMENT BY 50
CREATE SEQUENCE orders_id_seq START 1 INCREMENT 50 NO CYCLE;

-- Table uses the sequence
CREATE TABLE orders (
    id bigint NOT NULL DEFAULT nextval('orders_id_seq') PRIMARY KEY,
    ...
);
```

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

Applied automatically to all JPQL, `findById`, and Spring Data method queries.
**Not applied** to native queries — add `WHERE deleted_at IS NULL` manually in `@Query(nativeQuery = true)`.

---

## N+1 Prevention

### When to Use Each Strategy

| Strategy | When | Trade-off |
|----------|------|-----------|
| `JOIN FETCH` in JPQL | Association always needed in this method | Cartesian product risk with multiple collections |
| `@EntityGraph` | Dynamic per-method selection | Clean; avoids scattered JOIN FETCHes |
| `@BatchSize` | Large collections loaded lazily at scale | Trades N+1 for N/batch queries |
| DTO projection | Read-only listing | Fastest — skips entity lifecycle entirely |

```java
// ✅ JOIN FETCH — single query
@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.orders WHERE u.status = :status")
List<User> findWithOrders(@Param("status") String status);

// ✅ EntityGraph — declared at method level
@EntityGraph(attributePaths = {"orders", "orders.items"})
List<User> findByStatus(String status);

// ✅ BatchSize on field — IN clause batching
@OneToMany(mappedBy = "user", fetch = FetchType.LAZY)
@BatchSize(size = 20)
private List<Order> orders;
```

### Multiple Collections — Use Separate Queries

```java
// ❌ Cannot JOIN FETCH two bag collections simultaneously
// → HibernateException: cannot simultaneously fetch multiple bags

// ✅ Fetch in separate queries; Hibernate first-level cache deduplicates
@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.orders WHERE u.id IN :ids")
List<User> findWithOrders(@Param("ids") List<Long> ids);

@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.addresses WHERE u.id IN :ids")
List<User> findWithAddresses(@Param("ids") List<Long> ids);
```

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

    public static Specification<Order> createdAfter(OffsetDateTime from) {
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

## Pagination Strategies

### Offset Pagination — Good for ≤ 10K rows

```java
Page<Order> findByUserId(Long userId, Pageable pageable);

// Caller
orderRepository.findByUserId(userId,
    PageRequest.of(page, 20, Sort.by("createdAt").descending()));
```

### Keyset Pagination — Required for Large Tables

```java
@Query("""
    SELECT o FROM Order o
    WHERE o.userId = :userId
      AND deleted_at IS NULL
      AND (o.createdAt < :cursor
           OR (o.createdAt = :cursor AND o.id < :lastId))
    ORDER BY o.createdAt DESC, o.id DESC
    LIMIT :limit
    """)
List<Order> findPageAfterCursor(
    @Param("userId")  Long userId,
    @Param("cursor")  OffsetDateTime cursor,
    @Param("lastId")  Long lastId,
    @Param("limit")   int limit
);
```

---

## Projections

### Interface Projection

```java
public interface OrderSummary {
    Long getId();
    String getStatus();
    BigDecimal getTotalAmount();
}

List<OrderSummary> findByUserId(Long userId);
```

### DTO Projection

```java
public record OrderDto(Long id, String status, BigDecimal totalAmount) {}

@Query("""
    SELECT new com.example.dto.OrderDto(o.id, o.status, o.totalAmount)
    FROM Order o WHERE o.userId = :userId AND o.deletedAt IS NULL
    """)
List<OrderDto> findOrderDtosByUserId(@Param("userId") Long userId);
```

---

## Batch Writes

```java
// ✅ saveAll() — effective when Hibernate SEQUENCE strategy + batch_size configured
orderRepository.saveAll(orders);

// ✅ JdbcTemplate for high-volume (bypasses entity lifecycle)
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

> Batch inserts work correctly with `SEQUENCE` strategy + `allocationSize ≥ batch_size`.
> `IDENTITY` strategy disables batch inserts — another reason to prefer `SEQUENCE`.
