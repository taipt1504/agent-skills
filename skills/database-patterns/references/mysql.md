# MySQL Patterns — Schema, Indexing, Config

---

## Data Types

| Use Case | Type | Notes |
|----------|------|-------|
| Surrogate PK | `BIGINT UNSIGNED AUTO_INCREMENT` | UUID as PK causes B-tree fragmentation |
| UUID storage | `BINARY(16)` | `UUID_TO_BIN(UUID(), 1)` for time-ordered |
| UUID readable | `VARCHAR(36)` | Larger index; OK for low-write tables |
| Currency | `DECIMAL(10,2)` | Never `FLOAT`/`DOUBLE` |
| Status | `VARCHAR(20)` + CHECK or `ENUM(...)` | ENUM is compact; VARCHAR easier to evolve |
| Boolean | `TINYINT(1)` | No native BOOLEAN |
| Timestamps | `DATETIME(3)` | Millisecond precision; store in UTC; avoid `TIMESTAMP` (2038 limit) |
| JSON | `JSON` | MySQL 8+ native; index via generated columns |
| Long text | `TEXT` | Avoid in WHERE without prefix index |

---

## DDL Template -- utf8mb4 Required

Every `CREATE TABLE` must declare `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`.

```sql
CREATE TABLE orders (
    id           BIGINT UNSIGNED AUTO_INCREMENT NOT NULL,
    user_id      BIGINT UNSIGNED NOT NULL,
    status       VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    total_amount DECIMAL(10,2)   NOT NULL,
    note         TEXT            NULL,
    created_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at   DATETIME(3)     NULL DEFAULT NULL,
    PRIMARY KEY (id),
    INDEX idx_orders_user_id (user_id),
    INDEX idx_orders_status  (status),
    INDEX idx_orders_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## Indexing Strategy

### Composite Index -- Column Order Rule

1. Equality predicates first (highest cardinality)
2. Range predicates after equality
3. ORDER BY / GROUP BY columns last

```sql
CREATE INDEX idx_orders_user_status_created
    ON orders (user_id, status, created_at DESC) USING BTREE;
```

### Covering Index (No INCLUDE -- List All Columns)

MySQL has no `INCLUDE`. List every projected column in the key:

```sql
-- Query: SELECT id, status, total_amount FROM orders WHERE user_id = ?
-- All columns in index -> "Using index" (no table lookup)
CREATE INDEX idx_orders_user_covering
    ON orders (user_id, status, total_amount);
```

### Generated (Virtual) Column for Expression Indexes

```sql
ALTER TABLE users
    ADD COLUMN email_upper VARCHAR(255)
        GENERATED ALWAYS AS (UPPER(email)) VIRTUAL,
    ADD INDEX idx_users_email_upper (email_upper);

-- Optimizer picks up: WHERE UPPER(email) = UPPER('user@example.com')
```

### Invisible Indexes (MySQL 8.0.23+)

Test index removal without dropping:

```sql
ALTER TABLE orders ALTER INDEX idx_orders_status INVISIBLE;
-- Run EXPLAIN to verify no regression
ALTER TABLE orders ALTER INDEX idx_orders_status VISIBLE;
```

### Partial Index Workaround

MySQL has no `WHERE` clause on indexes. Use composite with discriminator as leading column:

```sql
CREATE INDEX idx_orders_active_user
    ON orders (status, user_id, created_at)
    COMMENT 'Optimised for status=ACTIVE queries';
```

---

## EXPLAIN

```sql
EXPLAIN SELECT o.id, o.status FROM orders o
WHERE o.status = 'PENDING' AND o.created_at > '2024-01-01';
```

| `type` | Meaning |
|--------|---------|
| `ALL` | Full table scan -- add index |
| `index` | Full index scan |
| `range` | Index range scan -- acceptable |
| `ref` | Non-unique index lookup -- good |
| `eq_ref` | Unique index lookup -- best for joins |
| `const` | Single-row PK/unique match -- best |

Key `Extra` values:
- `Using index` -- covering index (good)
- `Using filesort` -- add index on ORDER BY columns
- `Using temporary` -- refactor GROUP BY

### EXPLAIN ANALYZE (MySQL 8.0.18+)

```sql
EXPLAIN ANALYZE
SELECT o.id, SUM(oi.amount)
FROM orders o JOIN order_items oi ON oi.order_id = o.id
WHERE o.status = 'CONFIRMED' GROUP BY o.id;
-- Compare estimated_rows vs actual_rows; fix stale stats: ANALYZE TABLE orders;
```

---

## CTEs and Window Functions (MySQL 8.0+)

```sql
-- Recursive CTE
WITH RECURSIVE category_tree AS (
    SELECT id, parent_id, name, 0 AS depth
    FROM categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.parent_id, c.name, ct.depth + 1
    FROM categories c JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT * FROM category_tree ORDER BY depth, name;

-- Window function
SELECT id, user_id, total_amount,
    SUM(total_amount) OVER (
        PARTITION BY user_id ORDER BY created_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM orders WHERE deleted_at IS NULL;
```

---

## JPA Config (MySQL)

```yaml
spring:
  datasource:
    url: jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}?useUnicode=true&characterEncoding=UTF-8&serverTimezone=UTC
    driver-class-name: com.mysql.cj.jdbc.Driver
  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        dialect: org.hibernate.dialect.MySQLDialect
        default_batch_fetch_size: 20
        jdbc:
          batch_size: 100
          order_inserts: true
          order_updates: true
    open-in-view: false
```

Key: Use `@GeneratedValue(strategy = IDENTITY)` -- maps to `AUTO_INCREMENT`. MySQL has no sequences.

```java
@Entity
@Table(name = "orders")
@SQLRestriction("deleted_at IS NULL")
@DynamicUpdate
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Getter
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private OrderStatus status;

    @Column(name = "total_amount", nullable = false, precision = 10, scale = 2)
    private BigDecimal totalAmount;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @OneToMany(mappedBy = "order", fetch = FetchType.LAZY,
               cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();
}
```

---

## R2DBC Config (MySQL)

```yaml
spring:
  r2dbc:
    url: r2dbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}?serverZoneId=UTC&useUnicode=true&characterEncoding=UTF-8
    username: ${DB_USER}
    password: ${DB_PASS}
    pool:
      initial-size: 2
      max-size: 10
      max-idle-time: 10m
      max-create-connection-time: 30s
      validation-query: SELECT 1
  datasource:
    url: jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}?useUnicode=true&characterEncoding=UTF-8
    driver-class-name: com.mysql.cj.jdbc.Driver
  flyway:
    enabled: true
```

Driver dependency: `io.asyncer:r2dbc-mysql`

Note: Include `serverZoneId=UTC` to avoid datetime off-by-hours bugs.

Insert returning generated key (MySQL has no `RETURNING`):

```java
public Mono<Long> insert(CreateOrderCommand cmd) {
    return db.sql("INSERT INTO orders (user_id, status, total_amount, created_at) VALUES (:uid, :status, :amount, NOW(3))")
        .bind("uid",    cmd.userId())
        .bind("status", "PENDING")
        .bind("amount", cmd.totalAmount())
        .filter(s -> s.returnGeneratedValues("id"))
        .map(row -> row.get("id", Long.class))
        .one();
}
```

---

## Pool Sizing

Same formula as PostgreSQL:

```
pool_size = (vCPU * 2) + effective_spindle_count
```

HikariCP with MySQL-specific optimizations:

```yaml
spring:
  datasource:
    hikari:
      pool-name: HikariPool-Main
      maximum-pool-size: 10
      minimum-idle: 2
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000
      keepalive-time: 60000
      data-source-properties:
        cachePrepStmts: true
        prepStmtCacheSize: 250
        prepStmtCacheSqlLimit: 2048
        useServerPrepStmts: true
        rewriteBatchedStatements: true
        cacheResultSetMetadata: true
        elideSetAutoCommits: true
```

`rewriteBatchedStatements=true` is required for `saveAll()` batching to work.

---

## Isolation Levels (MySQL-Specific)

| Level | Phantom Read | Gap Locks | Deadlock Risk |
|-------|-------------|-----------|--------------|
| `READ_COMMITTED` | Possible | Minimal | Low |
| `REPEATABLE_READ` (default) | Prevented (gap locks) | Yes | Medium-High |
| `SERIALIZABLE` | Prevented | Full range | Highest |

`REPEATABLE_READ` **prevents** phantom reads in MySQL via gap locks. `READ_COMMITTED` **reduces** gap lock contention at the cost of phantom reads.

```java
@Transactional  // Default REPEATABLE_READ -- correct for financial ops
@Transactional(isolation = Isolation.READ_COMMITTED)  // Less contention
```

---

## Flyway Config (MySQL)

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false
    default-schema: ${DB_NAME}
    validate-on-migrate: true
    out-of-order: false
```

Migration header -- enforce charset:

```sql
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
```

---

## Deadlock Handling

MySQL auto-detects deadlocks and rolls back the younger TX (error 1213, SQLState 40001).

```java
@Retryable(
    retryFor = { MySQLTransactionRollbackException.class, CannotAcquireLockException.class },
    maxAttempts = 3,
    backoff = @Backoff(delay = 100, multiplier = 2, random = true)
)
@Transactional
public Order confirmOrder(Long id) { ... }
```
