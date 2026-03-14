# Flyway Migrations & Testing — PostgreSQL

---

## Flyway — PostgreSQL Configuration

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false          # true only when adding Flyway to an existing DB
    baseline-version: 0
    default-schema: public
    encoding: UTF-8
    validate-on-migrate: true
    out-of-order: false
  # Flyway requires JDBC datasource even in R2DBC services
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require
    username: ${DB_USER}
    password: ${DB_PASS}
    driver-class-name: org.postgresql.Driver
```

---

## Migration File Structure

```
src/main/resources/db/migration/
├── V1__create_users_table.sql
├── V2__create_orders_table.sql
├── V3__add_deleted_at_to_users.sql
├── V4__create_indexes.sql
└── R__refresh_orders_view.sql    # Repeatable — runs when checksum changes
```

Rules:
- Version prefix: `V{n}__{description}.sql` — **double underscore**
- `snake_case` description
- One logical change per migration
- Never modify an applied migration — create a new one

---

## Migration File Template

PostgreSQL encoding is set at the database level — no `SET NAMES` header needed (unlike MySQL). However, always set the search path:

```sql
-- V1__create_orders_table.sql
SET search_path TO public;

CREATE TABLE orders (
    id           bigint          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      bigint          NOT NULL,
    status       text            NOT NULL DEFAULT 'PENDING',
    total_amount numeric(10,2)   NOT NULL CHECK (total_amount >= 0),
    note         text            NULL,
    metadata     jsonb           NULL DEFAULT '{}',
    created_at   timestamptz     NOT NULL DEFAULT now(),
    updated_at   timestamptz     NOT NULL DEFAULT now(),
    deleted_at   timestamptz     NULL,
    CONSTRAINT fk_orders_users FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_orders_status CHECK (status IN ('PENDING', 'CONFIRMED', 'SHIPPED', 'CANCELLED'))
);

-- Always index FK columns in a separate statement (easier to track)
CREATE INDEX idx_orders_user_id  ON orders (user_id);
CREATE INDEX idx_orders_status   ON orders (status) WHERE deleted_at IS NULL;
CREATE INDEX idx_orders_created  ON orders (created_at DESC);

COMMENT ON TABLE  orders              IS 'Customer orders';
COMMENT ON COLUMN orders.deleted_at  IS 'Soft delete timestamp; NULL means active';
```

---

## Large Table Migration Strategies

Altering a large table with naive `ALTER TABLE` can lock the table for extended periods.

### Strategy 1 — `NOT VALID` + `VALIDATE CONSTRAINT` (Adding Constraints)

```sql
-- Step 1: Add constraint WITHOUT scanning existing rows (instant, no table lock)
ALTER TABLE orders
    ADD CONSTRAINT chk_orders_amount CHECK (total_amount >= 0) NOT VALID;

-- Step 2: Validate in the background (ShareUpdateExclusiveLock — reads/writes allowed)
-- Run during low-traffic window or scheduled maintenance
ALTER TABLE orders VALIDATE CONSTRAINT chk_orders_amount;
```

### Strategy 2 — `CONCURRENTLY` for Index Creation

```sql
-- Standard CREATE INDEX: blocks writes (ShareLock)
CREATE INDEX idx_orders_user_id ON orders (user_id);

-- CONCURRENTLY: no write block; takes longer but safe on production
CREATE INDEX CONCURRENTLY idx_orders_user_id ON orders (user_id);

-- NOTE: CONCURRENTLY cannot run inside a transaction block
-- In Flyway, disable transaction per migration for CONCURRENTLY statements:
```

```java
// Java-based Flyway migration for CONCURRENTLY DDL
@SuppressWarnings("unused")
public class V5__AddConcurrentIndex implements JavaMigration {

    @Override
    public boolean canExecuteInTransaction() {
        return false;   // Required for CONCURRENTLY
    }

    @Override
    public void migrate(Context context) throws Exception {
        context.getConnection().createStatement().execute(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_user_id ON orders (user_id)"
        );
    }

    @Override public Integer getChecksum() { return null; }
    @Override public MigrationVersion getVersion() { return MigrationVersion.fromVersion("5"); }
    @Override public String getDescription() { return "Add concurrent index on orders.user_id"; }
}
```

### Strategy 3 — Adding a Column with Default (PostgreSQL 11+)

```sql
-- PostgreSQL 11+: adding a column with a constant default is instant (no table rewrite)
ALTER TABLE orders ADD COLUMN priority smallint NOT NULL DEFAULT 0;

-- Before PG 11 or with volatile default: add nullable, backfill in batches, then add NOT NULL
ALTER TABLE orders ADD COLUMN priority smallint NULL;

-- Backfill in batches (no long-running lock)
DO $$
DECLARE batch_size INT := 1000;
        last_id   BIGINT := 0;
        max_id    BIGINT;
BEGIN
    SELECT MAX(id) INTO max_id FROM orders;
    WHILE last_id < max_id LOOP
        UPDATE orders SET priority = 0
        WHERE id > last_id AND id <= last_id + batch_size AND priority IS NULL;
        last_id := last_id + batch_size;
        PERFORM pg_sleep(0.1);  -- Throttle to avoid replication lag
    END LOOP;
END$$;

-- After backfill: set NOT NULL constraint (instant — no scan needed after PG knows all rows are non-null)
ALTER TABLE orders ALTER COLUMN priority SET NOT NULL;
ALTER TABLE orders ALTER COLUMN priority SET DEFAULT 0;
```

---

## Testcontainers — PostgreSQL Setup

### Shared Container (Recommended)

```java
// AbstractPostgresTest.java — extend in all integration test classes
@Testcontainers
public abstract class AbstractPostgresTest {

    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test")
        .withCommand("postgres", "-c", "shared_buffers=128MB", "-c", "max_connections=50")
        .withReuse(true);   // ~/.testcontainers.properties: testcontainers.reuse.enable=true

    @DynamicPropertySource
    static void configure(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url",      POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username",  POSTGRES::getUsername);
        registry.add("spring.datasource.password",  POSTGRES::getPassword);
        // For R2DBC services:
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:postgresql://test:test@localhost:" + POSTGRES.getMappedPort(5432) + "/testdb");
        registry.add("spring.r2dbc.username", () -> "test");
        registry.add("spring.r2dbc.password", () -> "test");
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
class OrderRepositoryIntegrationTest extends AbstractPostgresTest {

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
| `deleteAll()` in `@BeforeEach` | Default — simple, any test type | Slower than rollback; order by FK dependencies |
| `@Transactional` + rollback | Synchronous Spring MVC tests only | Fast; does NOT work with async, WebFlux, or multi-datasource |
| `TRUNCATE ... CASCADE` | Faster than `DELETE` for large tables; resets sequences | Use `RESTART IDENTITY CASCADE` to reset sequences too |
| Separate schema per test class | Parallel test execution | Complex; good for CI with `-PmaxParallelForks` |

```java
// TRUNCATE with sequence reset (fastest cleanup)
@BeforeEach
void clean() {
    jdbcTemplate.execute("TRUNCATE TABLE order_items, orders RESTART IDENTITY CASCADE");
}

// @Transactional rollback — synchronous tests only
@SpringBootTest
@Transactional   // Rolls back after each test
class OrderServiceTest extends AbstractPostgresTest {
    @Test
    void shouldCreateOrder() { ... }
}
```

---

## Flyway Repair (Broken Migration)

```bash
# If a migration fails mid-way and leaves a checksum mismatch:
./gradlew flywayRepair

# Or force repair via SQL (last resort)
DELETE FROM flyway_schema_history WHERE version = '5' AND success = false;
```

Never use `flyway.cleanDisabled=false` in production — it drops all objects.
