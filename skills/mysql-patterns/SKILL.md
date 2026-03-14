---
name: mysql-patterns
description: MySQL 8.x best practices for Java Spring applications. Use when writing MySQL queries, designing schemas, configuring JPA/Hibernate with MySQL, or reviewing MySQL-specific performance. Covers indexing strategies, query optimization, connection pooling (HikariCP), transaction management, and JPA gotchas.
---

# MySQL Patterns for Java Spring

Production-ready MySQL patterns for Java 17+ / Spring Boot 3.x.

## Quick Reference

| Category | When to Use | Reference |
|----------|-------------|-----------|
| Schema Design | Creating/altering tables | [Schema Patterns](#schema-patterns) |
| Indexing | Slow queries, EXPLAIN analysis | [Indexing Strategy](#indexing-strategy) |
| JPA/Hibernate | Entity mapping, N+1 problems | [JPA Best Practices](#jpa-best-practices) |
| Connection Pool | HikariCP tuning | [Connection Pool](#connection-pool-hikaricp) |
| Query Optimization | EXPLAIN, slow query log | [Query Optimization](#query-optimization) |
| Transactions | Isolation, deadlocks | [Transaction Management](#transaction-management) |
| Testing | Testcontainers MySQL | [Testing](#testing) |

---

## Schema Patterns

### Naming Conventions

```sql
-- ✅ Snake case, plural table names, singular column names
CREATE TABLE orders (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT UNSIGNED NOT NULL,
    status      ENUM('PENDING','CONFIRMED','SHIPPED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    total_amount DECIMAL(10,2) NOT NULL,
    created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    INDEX idx_orders_user_id (user_id),
    INDEX idx_orders_status (status),
    INDEX idx_orders_created_at (created_at)
);
```

### Data Types — Best Choices

| Use Case | Recommended Type | Notes |
|----------|-----------------|-------|
| Surrogate PK | `BIGINT UNSIGNED AUTO_INCREMENT` | Avoid UUID as PK (index fragmentation) |
| UUID/GUID | `BINARY(16)` or `VARCHAR(36)` | Use UUID_TO_BIN() for storage |
| Currency | `DECIMAL(10,2)` | Never FLOAT/DOUBLE for money |
| Status/Enum | `ENUM(...)` or tiny `TINYINT` | ENUM is readable; TINYINT is flexible |
| Boolean | `TINYINT(1)` | MySQL has no native BOOLEAN |
| Timestamp | `DATETIME(3)` | Millisecond precision; use UTC |
| JSON | `JSON` column | MySQL 8+ native JSON type |
| Text content | `TEXT` or `VARCHAR(n)` | TEXT for >65K chars |

### Soft Deletes

```sql
-- ✅ Use deleted_at timestamp for audit trails
ALTER TABLE users ADD COLUMN deleted_at DATETIME(3) NULL DEFAULT NULL;
ALTER TABLE users ADD INDEX idx_users_deleted_at (deleted_at);

-- Filter in queries
SELECT * FROM users WHERE deleted_at IS NULL;

-- JPA @Where equivalent
```

---

## Indexing Strategy

### Index Rules

```sql
-- ✅ Composite index: most selective column FIRST
-- Query: WHERE user_id = ? AND status = ? ORDER BY created_at DESC
CREATE INDEX idx_orders_user_status_created
    ON orders(user_id, status, created_at DESC);

-- ❌ Wrong order — full index not used
CREATE INDEX idx_orders_status_user
    ON orders(status, user_id);  -- status has low cardinality
```

### Covering Index (Avoid Table Lookup)

```sql
-- Query: SELECT id, status FROM orders WHERE user_id = ?
-- Covering index includes all required columns
CREATE INDEX idx_orders_user_covering
    ON orders(user_id) INCLUDE (status);  -- MySQL 8.0.13+
-- or: ON orders(user_id, status)
```

### EXPLAIN Analysis

```sql
-- Always run EXPLAIN before shipping queries
EXPLAIN SELECT o.id, o.status, u.email
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.status = 'PENDING' AND o.created_at > '2024-01-01';

-- ❌ Bad: type=ALL (full table scan), Extra=Using filesort
-- ✅ Good: type=ref or range, key=<index_name>, Extra=Using index
```

### Key `EXPLAIN` Output

| `type` | Meaning | Action |
|--------|---------|--------|
| `ALL` | Full table scan | Add index |
| `index` | Full index scan | May need better index |
| `range` | Index range scan | Usually acceptable |
| `ref` | Index lookup | Good |
| `eq_ref` | Unique index lookup | Best for joins |
| `const` | Single row match | Best |

---

## JPA Best Practices

### Entity Design

```java
// ✅ Correct JPA Entity for MySQL
@Entity
@Table(name = "orders", indexes = {
    @Index(name = "idx_orders_user_id", columnList = "user_id"),
    @Index(name = "idx_orders_status", columnList = "status")
})
@DynamicUpdate  // Only update changed columns
@NoArgsConstructor(access = AccessLevel.PROTECTED)  // JPA requires no-arg
@Getter
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private OrderStatus status;

    @Column(name = "total_amount", nullable = false, precision = 10, scale = 2)
    private BigDecimal totalAmount;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @OneToMany(mappedBy = "order", fetch = FetchType.LAZY, cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}
```

### Avoid N+1 — Use JOIN FETCH or EntityGraph

```java
// ❌ N+1: loads each user's orders separately
List<User> users = userRepository.findAll();
users.forEach(u -> u.getOrders().size()); // N+1 queries!

// ✅ JOIN FETCH in JPQL
@Query("SELECT DISTINCT u FROM User u LEFT JOIN FETCH u.orders WHERE u.status = :status")
List<User> findWithOrders(@Param("status") UserStatus status);

// ✅ EntityGraph for dynamic fetching
@EntityGraph(attributePaths = {"orders", "orders.items"})
List<User> findByStatus(UserStatus status);

// ✅ Batch fetching (add to persistence.xml or @BatchSize)
@BatchSize(size = 20)
@OneToMany(mappedBy = "user", fetch = FetchType.LAZY)
private List<Order> orders;
```

### Pagination Best Practices

```java
// ✅ Offset pagination for small datasets
Page<Order> findByUserId(Long userId, Pageable pageable);

// ✅ Keyset pagination (cursor-based) for large datasets
// Avoids OFFSET performance degradation
@Query("""
    SELECT o FROM Order o
    WHERE o.userId = :userId
    AND (o.createdAt < :cursor OR (o.createdAt = :cursor AND o.id < :lastId))
    ORDER BY o.createdAt DESC, o.id DESC
    LIMIT :limit
    """)
List<Order> findPageAfterCursor(@Param("userId") Long userId,
                                 @Param("cursor") LocalDateTime cursor,
                                 @Param("lastId") Long lastId,
                                 @Param("limit") int limit);
```

---

## Connection Pool (HikariCP)

```yaml
# application.yml — Production HikariCP config
spring:
  datasource:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      pool-name: HikariPool-Main
      maximum-pool-size: 20           # CPU_CORES * 2 + disk_spindles
      minimum-idle: 5
      connection-timeout: 30000       # 30s — fail fast if no connection
      idle-timeout: 600000            # 10 min — return idle connections
      max-lifetime: 1800000           # 30 min — < MySQL wait_timeout (default 8h)
      keepalive-time: 60000           # 1 min — prevent stale connections
      connection-test-query: SELECT 1
      data-source-properties:
        cachePrepStmts: true
        prepStmtCacheSize: 250
        prepStmtCacheSqlLimit: 2048
        useServerPrepStmts: true
        useLocalSessionState: true
        rewriteBatchedStatements: true
        cacheResultSetMetadata: true
        cacheServerConfiguration: true
        elideSetAutoCommits: true
        maintainTimeStats: false
```

---

## Query Optimization

### Batch Operations

```java
// ❌ Slow: individual inserts in loop
for (Order order : orders) {
    orderRepository.save(order);  // N INSERT statements
}

// ✅ Batch insert with saveAll
orderRepository.saveAll(orders);  // single batch with rewriteBatchedStatements=true

// ✅ Native batch insert
@Modifying
@Query(value = "INSERT INTO orders (user_id, status, total_amount) VALUES ?1", nativeQuery = true)
void batchInsert(List<Object[]> values);

// ✅ Spring Data JDBC batch
jdbcTemplate.batchUpdate("INSERT INTO orders (user_id, status) VALUES (?, ?)",
    orders, 100, (ps, order) -> {
        ps.setLong(1, order.getUserId());
        ps.setString(2, order.getStatus().name());
    });
```

### Projections (Avoid Loading Full Entity)

```java
// ✅ Interface projection — only fetch needed columns
public interface OrderSummary {
    Long getId();
    String getStatus();
    BigDecimal getTotalAmount();
}

List<OrderSummary> findByUserId(Long userId);

// ✅ DTO projection
@Query("SELECT new com.example.dto.OrderDto(o.id, o.status, o.totalAmount) FROM Order o WHERE o.userId = :userId")
List<OrderDto> findOrderDtosByUserId(@Param("userId") Long userId);
```

---

## Transaction Management

```java
// ✅ Service-level transaction
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)  // Default read-only for all queries
public class OrderService {

    private final OrderRepository orderRepository;

    // Override for writes
    @Transactional  // readOnly = false
    public Order create(CreateOrderCommand cmd) {
        Order order = Order.create(cmd);
        return orderRepository.save(order);
    }

    // Read-only — uses read replica if configured
    public List<Order> findByUser(Long userId) {
        return orderRepository.findByUserId(userId);
    }

    // Nested transaction (uses SAVEPOINT)
    @Transactional(propagation = Propagation.NESTED)
    public void processItem(OrderItem item) {
        // Can rollback independently
    }
}
```

### Isolation Levels

```java
// ❌ Default REPEATABLE_READ in MySQL — may cause phantom reads for range queries
@Transactional

// ✅ READ_COMMITTED for most OLTP workloads
@Transactional(isolation = Isolation.READ_COMMITTED)

// ✅ SERIALIZABLE only for critical financial operations
@Transactional(isolation = Isolation.SERIALIZABLE)
```

---

## Testing

### Testcontainers MySQL

```java
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class OrderRepositoryTest {

    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test")
        .withReuse(true);  // Reuse container across test classes

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
    }

    @Autowired
    private OrderRepository orderRepository;

    @BeforeEach
    void setUp() {
        orderRepository.deleteAll();
    }

    @Test
    void shouldPersistOrder() {
        var order = Order.create(userId, List.of(item));
        var saved = orderRepository.save(order);
        assertThat(saved.getId()).isNotNull();
    }
}
```

---

## Common Anti-Patterns

| ❌ Anti-Pattern | ✅ Fix |
|----------------|--------|
| `SELECT *` in queries | Select only required columns |
| UUID as primary key | Use BIGINT AUTO_INCREMENT; store UUID as BINARY(16) |
| Missing indexes on FK columns | Always index foreign keys |
| `fetch = EAGER` on collections | Always use LAZY; load with JOIN FETCH when needed |
| `@Transactional` on repository | Put `@Transactional` on service, not repository |
| Too many HikariCP connections | CPU * 2 + disk; more is not better |
| `FLOAT`/`DOUBLE` for money | Use `DECIMAL(10,2)` always |
| No connection timeout | Always set `connectionTimeout` and `max-lifetime` |
