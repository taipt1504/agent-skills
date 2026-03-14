---
name: database-migrations
description: Zero-downtime database migration patterns — Flyway conventions, expand-contract, safety checklists, Testcontainers validation
---

# Database Migrations

## When to Activate

- Creating or reviewing Flyway/Liquibase migrations
- Changing database schema (columns, tables, indexes, constraints)
- Planning zero-downtime deployments with schema changes
- Setting up migration testing with Testcontainers

## Flyway Naming Convention

```
V{major}.{minor}__{description}.sql     — Versioned (one-time)
R__{description}.sql                     — Repeatable (views, functions)
U{major}.{minor}__{description}.sql      — Undo (if enabled)
```

Examples:
```
V1.0__create_users_table.sql
V1.1__add_email_to_users.sql
V1.2__create_orders_table.sql
R__update_order_summary_view.sql
```

**Rules:**
- Double underscore `__` separates version from description
- Use lowercase with underscores for descriptions
- Never edit an applied migration — create a new one instead
- Keep migrations small and focused (one logical change per file)

## Expand-Contract Pattern (Zero Downtime)

For breaking schema changes, use 3-phase deployment:

### Phase 1: Expand (Add New)

```sql
-- V2.0__add_email_column.sql
ALTER TABLE users ADD COLUMN email VARCHAR(255);
-- Allow NULL initially — old code doesn't know about this column
```

### Phase 2: Migrate (Backfill + Deploy New Code)

```sql
-- V2.1__backfill_email.sql
-- Run as a batch job, not a single UPDATE
UPDATE users SET email = username || '@legacy.example.com'
WHERE email IS NULL
LIMIT 1000; -- Process in batches
```

Deploy new code that writes to BOTH old and new columns.

### Phase 3: Contract (Remove Old)

```sql
-- V2.2__make_email_not_null.sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
-- Only after verifying all rows have email values

-- V2.3__drop_old_username_column.sql (separate deployment)
ALTER TABLE users DROP COLUMN username;
-- Only after old code is fully decommissioned
```

## Safety Rules

### Always Safe

```sql
-- Adding a nullable column
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- Adding an index (PostgreSQL — non-blocking)
CREATE INDEX CONCURRENTLY idx_users_email ON users(email);

-- Adding a table
CREATE TABLE audit_log (...);
```

### Requires Caution

```sql
-- Adding NOT NULL column — MUST have DEFAULT
-- BAD:
ALTER TABLE users ADD COLUMN role VARCHAR(20) NOT NULL;
-- GOOD:
ALTER TABLE users ADD COLUMN role VARCHAR(20) NOT NULL DEFAULT 'user';

-- Renaming column — use expand-contract
-- BAD: ALTER TABLE users RENAME COLUMN name TO full_name;
-- GOOD: Add new column, migrate data, drop old column (3 deployments)
```

### Never in Production

```sql
-- DROP TABLE without backup verification
-- DROP COLUMN without expand-contract
-- ALTER COLUMN to a smaller type (data loss)
-- TRUNCATE TABLE
```

## MySQL vs PostgreSQL Differences

| Operation | PostgreSQL | MySQL |
|-----------|-----------|-------|
| Add column | Non-blocking | Blocks (copies table in MySQL < 8.0) |
| Add index | `CREATE INDEX CONCURRENTLY` | `ALTER TABLE ... ADD INDEX` (online DDL in 8.0+) |
| Change column type | May rewrite table | `ALTER TABLE ... MODIFY` (online DDL) |
| Default values | Instant for new rows | Instant (8.0.12+) |
| Transactional DDL | Yes (all DDL in transaction) | No (implicit commit) |

### PostgreSQL-Specific

```sql
-- Use CONCURRENTLY for indexes (non-blocking)
CREATE INDEX CONCURRENTLY idx_orders_status ON orders(status);

-- Advisory locks for migrations
SELECT pg_advisory_lock(12345);
-- ... run migration ...
SELECT pg_advisory_unlock(12345);
```

### MySQL-Specific

```sql
-- Online DDL: ALGORITHM=INPLACE avoids table copy
ALTER TABLE orders ADD INDEX idx_status (status), ALGORITHM=INPLACE, LOCK=NONE;

-- pt-online-schema-change for large tables
-- Use when ALTER would lock table for too long
```

## Testcontainers Validation

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
        // Flyway runs automatically on startup
        // If we get here, all migrations applied successfully
    }

    @Test
    void shouldHaveExpectedSchema() {
        // Query information_schema to verify table structure
        // Ensures migrations produce the expected result
    }
}
```

## Pre-Migration Checklist

- [ ] Migration file follows naming convention `V{version}__{description}.sql`
- [ ] No `DROP` without expand-contract pattern
- [ ] `ADD COLUMN NOT NULL` includes `DEFAULT` value
- [ ] Large table changes use online DDL or pt-online-schema-change
- [ ] Indexes created with `CONCURRENTLY` (PostgreSQL)
- [ ] Migration tested with Testcontainers
- [ ] Rollback plan documented (separate undo migration or manual steps)
- [ ] Data backfill runs in batches, not single statements
- [ ] No sensitive data in migration files (credentials, PII)
