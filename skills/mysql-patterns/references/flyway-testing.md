# Flyway Migrations & Testing — MySQL

---

## Flyway — MySQL Configuration

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false        # true only when adding Flyway to an existing DB
    baseline-version: 0
    default-schema: ${DB_NAME}
    encoding: UTF-8
    validate-on-migrate: true
    out-of-order: false               # Never allow out-of-order in production
    placeholders:
      schema: ${DB_NAME}
  # Flyway requires a JDBC datasource even in R2DBC services
  datasource:
    url: jdbc:mysql://${DB_HOST}:3306/${DB_NAME}?useUnicode=true&characterEncoding=UTF-8&serverTimezone=UTC
    username: ${DB_USER}
    password: ${DB_PASS}
    driver-class-name: com.mysql.cj.jdbc.Driver
```

---

## Migration File Header — utf8mb4 Enforcement

Every migration file must begin with the charset header to guarantee correct encoding regardless of server defaults:

```sql
-- V1__create_orders_table.sql
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

CREATE TABLE orders (
    id           BIGINT UNSIGNED AUTO_INCREMENT NOT NULL,
    user_id      BIGINT UNSIGNED NOT NULL,
    status       VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    total_amount DECIMAL(10,2)   NOT NULL,
    created_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at   DATETIME(3)     NULL DEFAULT NULL,
    PRIMARY KEY (id),
    INDEX idx_orders_user_id (user_id),
    INDEX idx_orders_status  (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### Naming Convention

```
db/migration/
├── V1__create_orders_table.sql
├── V2__add_order_items_table.sql
├── V3__add_deleted_at_to_users.sql
└── R__refresh_orders_view.sql     # Repeatable migration (R__) — runs when checksum changes
```

Rules:
- Version prefix: `V{n}__{description}.sql` — double underscore
- All lower_snake_case description
- One logical change per file
- Never modify an applied migration — create a new one instead

---

## Large Table Migration Strategies

Altering a large table (> 1M rows) with a standard `ALTER TABLE` causes a full table rebuild and can lock the table for minutes.

### Option 1 — MySQL 8.0 Online DDL (Adding Columns / Indexes)

```sql
-- ALGORITHM=INSTANT: adds column metadata only; no table rebuild (MySQL 8.0.29+)
ALTER TABLE orders
    ADD COLUMN priority TINYINT NOT NULL DEFAULT 0,
    ALGORITHM=INSTANT;

-- ALGORITHM=INPLACE, LOCK=NONE: builds index in background without blocking reads/writes
ALTER TABLE orders
    ADD INDEX idx_orders_priority (priority),
    ALGORITHM=INPLACE, LOCK=NONE;
```

Check support before use:
```sql
-- Confirm online DDL support for the change
ALTER TABLE orders ADD COLUMN test_col INT, ALGORITHM=INSTANT;
-- If error: "ALGORITHM=INSTANT is not supported" → fall back to pt-osc
ROLLBACK; -- (DDL is auto-committed; drop manually if needed)
```

### Option 2 — pt-online-schema-change (Percona Toolkit)

Use when MySQL online DDL is insufficient (e.g., modifying column type, removing column):

```bash
# 1. Install percona-toolkit
# 2. Run with --dry-run first to verify
pt-online-schema-change \
  --alter "MODIFY COLUMN status VARCHAR(30) NOT NULL DEFAULT 'PENDING'" \
  --host=localhost --user=root --password=secret \
  --database=mydb --table=orders \
  --chunk-size=1000 \
  --sleep=0.05 \       # Throttle writes to avoid replication lag
  --dry-run

# 3. Execute after validating dry-run output
pt-online-schema-change ... --execute
```

### Flyway Wrapper for Large Migrations

```java
// Use Java-based Flyway migration for pt-osc or conditional DDL
public class V5__LargeTableMigration implements JavaMigration {
    @Override
    public void migrate(Context context) throws Exception {
        // Execute pt-osc via ProcessBuilder or delegate to ops team
        // Log migration steps for audit
    }
}
```

---

## Testcontainers — MySQL Setup

### Shared Container (Recommended)

```java
// AbstractMySQLTest.java — shared across all test classes
@Testcontainers
public abstract class AbstractMySQLTest {

    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.0")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test")
        .withCommand(
            "--character-set-server=utf8mb4",
            "--collation-server=utf8mb4_unicode_ci",
            "--explicit_defaults_for_timestamp=ON"
        )
        .withReuse(true);    // Requires ~/.testcontainers.properties: testcontainers.reuse.enable=true

    @DynamicPropertySource
    static void configure(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url",       MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username",  MYSQL::getUsername);
        registry.add("spring.datasource.password",  MYSQL::getPassword);
        // For R2DBC services:
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:mysql://test:test@localhost:" + MYSQL.getMappedPort(3306) + "/testdb");
    }
}
```

Enable container reuse — create `~/.testcontainers.properties`:
```properties
testcontainers.reuse.enable=true
```

### Integration Test Class

```java
@SpringBootTest
@ActiveProfiles("test")
class OrderRepositoryIntegrationTest extends AbstractMySQLTest {

    @Autowired private OrderRepository orderRepository;

    @BeforeEach
    void clean() {
        orderRepository.deleteAll();
    }

    @Test
    void shouldPersistAndFindOrder() {
        var order = Order.create(1L, BigDecimal.TEN);
        var saved = orderRepository.save(order);

        assertThat(saved.getId()).isNotNull();
        assertThat(orderRepository.findById(saved.getId())).isPresent();
    }
}
```

---

## Test Cleanup Strategy

| Strategy | When to Use | Trade-offs |
|----------|-------------|-----------|
| `deleteAll()` in `@BeforeEach` | Default — simple, works for any test | Slower than rollback; no FK ordering issues if `cascade = ALL` |
| `@Transactional` + rollback | Unit / slice tests with no async code | Fast; does NOT work with `@Async`, reactive code, or multi-datasource |
| `@Sql` with `DELETE` scripts | When FK constraints require order | Explicit control; more boilerplate |
| Separate schema per test class | Parallel test execution | Complex setup; good for CI performance |

```java
// @Transactional rollback — works only for synchronous Spring MVC tests
@SpringBootTest
@Transactional     // Rolls back after each test — no deleteAll() needed
class OrderServiceTest extends AbstractMySQLTest {
    @Test
    void shouldCreateOrder() { ... }  // DB state reverted after each test
}

// deleteAll() — use for reactive / async tests
@BeforeEach
void clean() {
    orderRepository.deleteAll();   // Blocking OK in @BeforeEach (test thread)
}
```
