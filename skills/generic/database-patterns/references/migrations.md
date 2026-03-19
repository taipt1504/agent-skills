# Database Migrations -- Flyway Patterns

---

## Flyway Naming Convention

```
V{major}.{minor}__{description}.sql     -- Versioned (one-time)
R__{description}.sql                     -- Repeatable (views, functions)
U{major}.{minor}__{description}.sql      -- Undo (if enabled)
```

Examples:

```
db/migration/
├── V1.0__create_users_table.sql
├── V1.1__add_email_to_users.sql
├── V1.2__create_orders_table.sql
├── V4__create_indexes.sql
└── R__update_order_summary_view.sql
```

Rules:
- Double underscore `__` separates version from description
- `snake_case` descriptions
- One logical change per migration
- Never edit an applied migration -- create a new one

---

## Flyway Configuration

### PostgreSQL

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false
    default-schema: public
    encoding: UTF-8
    validate-on-migrate: true
    out-of-order: false
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require
    driver-class-name: org.postgresql.Driver
```

Migration header:

```sql
SET search_path TO public;
```

### MySQL

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false
    default-schema: ${DB_NAME}
    encoding: UTF-8
    validate-on-migrate: true
    out-of-order: false
  datasource:
    url: jdbc:mysql://${DB_HOST}:3306/${DB_NAME}?useUnicode=true&characterEncoding=UTF-8&serverTimezone=UTC
    driver-class-name: com.mysql.cj.jdbc.Driver
```

Migration header (enforce charset):

```sql
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
```

---

## Expand-Contract Pattern (Zero Downtime)

For breaking schema changes, use 3-phase deployment:

### Phase 1: Expand (Add New)

```sql
-- V2.0__add_email_column.sql
ALTER TABLE users ADD COLUMN email VARCHAR(255);
-- Allow NULL initially -- old code doesn't know about this column
```

### Phase 2: Migrate (Backfill + Deploy New Code)

```sql
-- V2.1__backfill_email.sql
-- Run as batch job, not single UPDATE
UPDATE users SET email = username || '@legacy.example.com'
WHERE email IS NULL
LIMIT 1000; -- Process in batches
```

Deploy new code that writes to BOTH old and new columns.

### Phase 3: Contract (Remove Old)

```sql
-- V2.2__make_email_not_null.sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
-- Only after verifying all rows have values

-- V2.3__drop_old_username_column.sql (separate deployment)
ALTER TABLE users DROP COLUMN username;
-- Only after old code is fully decommissioned
```

---

## Safety Rules

### Always Safe

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);                      -- Nullable column
CREATE INDEX CONCURRENTLY idx_users_email ON users(email);           -- PG non-blocking
ALTER TABLE orders ADD INDEX idx_status (status), ALGORITHM=INPLACE; -- MySQL online DDL
CREATE TABLE audit_log (...);                                        -- New table
```

### Requires Caution

```sql
-- ADD NOT NULL column -- MUST have DEFAULT
ALTER TABLE users ADD COLUMN role VARCHAR(20) NOT NULL DEFAULT 'user';

-- Rename column -- use expand-contract (3 deployments)
-- NEVER: ALTER TABLE users RENAME COLUMN name TO full_name;
```

### Never in Production

- `DROP TABLE` without backup verification
- `DROP COLUMN` without expand-contract
- `ALTER COLUMN` to smaller type (data loss)
- `TRUNCATE TABLE`

---

## Large Table Strategies

### PostgreSQL

#### NOT VALID + VALIDATE CONSTRAINT

```sql
-- Step 1: Add constraint without scanning existing rows (instant)
ALTER TABLE orders
    ADD CONSTRAINT chk_orders_amount CHECK (total_amount >= 0) NOT VALID;

-- Step 2: Validate in background (ShareUpdateExclusiveLock -- reads/writes allowed)
ALTER TABLE orders VALIDATE CONSTRAINT chk_orders_amount;
```

#### CREATE INDEX CONCURRENTLY

```sql
CREATE INDEX CONCURRENTLY idx_orders_user_id ON orders (user_id);
-- Cannot run inside a transaction block
```

Flyway wrapper (required for CONCURRENTLY):

```java
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

#### Adding Column with Default (PG 11+)

```sql
-- Instant (no table rewrite) for constant defaults
ALTER TABLE orders ADD COLUMN priority smallint NOT NULL DEFAULT 0;

-- For volatile defaults or pre-PG 11: add nullable, backfill in batches, then NOT NULL
ALTER TABLE orders ADD COLUMN priority smallint NULL;

DO $$
DECLARE batch_size INT := 1000; last_id BIGINT := 0; max_id BIGINT;
BEGIN
    SELECT MAX(id) INTO max_id FROM orders;
    WHILE last_id < max_id LOOP
        UPDATE orders SET priority = 0
        WHERE id > last_id AND id <= last_id + batch_size AND priority IS NULL;
        last_id := last_id + batch_size;
        PERFORM pg_sleep(0.1);  -- Throttle to avoid replication lag
    END LOOP;
END$$;

ALTER TABLE orders ALTER COLUMN priority SET NOT NULL;
ALTER TABLE orders ALTER COLUMN priority SET DEFAULT 0;
```

### MySQL

#### Online DDL (MySQL 8.0+)

```sql
-- ALGORITHM=INSTANT: metadata-only change (MySQL 8.0.29+)
ALTER TABLE orders ADD COLUMN priority TINYINT NOT NULL DEFAULT 0, ALGORITHM=INSTANT;

-- ALGORITHM=INPLACE: background index build, no blocking
ALTER TABLE orders ADD INDEX idx_orders_priority (priority), ALGORITHM=INPLACE, LOCK=NONE;
```

#### pt-online-schema-change (Percona Toolkit)

Use when online DDL is insufficient (column type change, column removal):

```bash
pt-online-schema-change \
  --alter "MODIFY COLUMN status VARCHAR(30) NOT NULL DEFAULT 'PENDING'" \
  --host=localhost --user=root --password=secret \
  --database=mydb --table=orders \
  --chunk-size=1000 \
  --sleep=0.05 \
  --dry-run

# Execute after validating dry-run
pt-online-schema-change ... --execute
```

---

## PostgreSQL vs MySQL DDL Differences

| Operation | PostgreSQL | MySQL |
|-----------|-----------|-------|
| Add column | Non-blocking | Blocks (< 8.0); INSTANT (8.0.29+) |
| Add index | `CREATE INDEX CONCURRENTLY` | `ALGORITHM=INPLACE, LOCK=NONE` |
| Change column type | May rewrite table | `ALTER TABLE ... MODIFY` (online DDL) |
| Default values | Instant for constant defaults (PG 11+) | Instant (8.0.12+) |
| Transactional DDL | Yes (all DDL in transaction) | No (implicit commit) |
| Advisory locks | `pg_advisory_lock(id)` | Not available |

---

## Testcontainers Validation

### PostgreSQL

```java
@SpringBootTest
@Testcontainers
class MigrationValidationIT {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15")
        .withDatabaseName("testdb");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.flyway.enabled", () -> true);
    }

    @Test
    void shouldApplyAllMigrationsSuccessfully() {
        // Flyway runs on startup; reaching here means all migrations applied
    }
}
```

### MySQL

```java
@SpringBootTest
@Testcontainers
class MigrationValidationIT {

    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0")
        .withDatabaseName("testdb")
        .withCommand("--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysql::getJdbcUrl);
        registry.add("spring.datasource.username", mysql::getUsername);
        registry.add("spring.datasource.password", mysql::getPassword);
        registry.add("spring.flyway.enabled", () -> true);
    }

    @Test
    void shouldApplyAllMigrationsSuccessfully() {
        // Flyway runs on startup; reaching here means all migrations applied
    }
}
```

### Shared Container Base Class

```java
@Testcontainers
public abstract class AbstractPostgresTest {

    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test").withPassword("test")
        .withCommand("postgres", "-c", "shared_buffers=128MB", "-c", "max_connections=50")
        .withReuse(true);

    @DynamicPropertySource
    static void configure(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url",      POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username",  POSTGRES::getUsername);
        registry.add("spring.datasource.password",  POSTGRES::getPassword);
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:postgresql://test:test@localhost:" + POSTGRES.getMappedPort(5432) + "/testdb");
        registry.add("spring.r2dbc.username", () -> "test");
        registry.add("spring.r2dbc.password", () -> "test");
    }
}
```

Enable container reuse in `~/.testcontainers.properties`:

```properties
testcontainers.reuse.enable=true
```

---

## Test Cleanup Strategies

| Strategy | When | Trade-offs |
|----------|------|-----------|
| `deleteAll()` in `@BeforeEach` | Default -- simple | Slower; order by FK deps |
| `@Transactional` rollback | Synchronous MVC tests only | Fast; fails with async/WebFlux |
| `TRUNCATE ... CASCADE` (PG) | Large tables | Fastest; `RESTART IDENTITY CASCADE` resets sequences |
| `@Sql` with DELETE scripts | FK ordering control | Explicit; more boilerplate |
| Separate schema per test class | Parallel execution | Complex; good for CI |

```java
// TRUNCATE (fastest -- PostgreSQL)
@BeforeEach
void clean() {
    jdbcTemplate.execute("TRUNCATE TABLE order_items, orders RESTART IDENTITY CASCADE");
}

// @Transactional rollback (synchronous tests only)
@SpringBootTest
@Transactional
class OrderServiceTest extends AbstractPostgresTest {
    @Test void shouldCreateOrder() { ... }
}
```

---

## Pre-Migration Checklist

- [ ] Migration file follows naming convention `V{version}__{description}.sql`
- [ ] No `DROP` without expand-contract pattern
- [ ] `ADD COLUMN NOT NULL` includes `DEFAULT` value
- [ ] Large table changes use online DDL or pt-online-schema-change
- [ ] Indexes created with `CONCURRENTLY` (PG) or `INPLACE` (MySQL)
- [ ] Migration tested with Testcontainers
- [ ] Rollback plan documented
- [ ] Data backfill runs in batches, not single statements
- [ ] No sensitive data in migration files

---

## Flyway Repair

```bash
# If migration fails mid-way with checksum mismatch:
./gradlew flywayRepair

# Or via SQL (last resort):
DELETE FROM flyway_schema_history WHERE version = '5' AND success = false;
```

Never use `flyway.cleanDisabled=false` in production.
