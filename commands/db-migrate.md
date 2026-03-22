---
name: db-migrate
description: Create and validate Flyway database migrations for schema changes. Supports MySQL and PostgreSQL.
---

# /db-migrate -- Database Migration Workflow

Create and validate a Flyway database migration for schema changes.

## SDD Notice

Schema changes are a **spec-required task type** per the SDD workflow. For non-trivial migrations (new tables, column type changes, data migrations):
- Run `/plan` first to analyze impact
- Run `/spec` to define the migration spec (DDL, zero-downtime strategy, rollback)
- Exception: Simple column additions with NULL default can skip SDD

## Instructions

1. Gather migration context:

```bash
# Find existing migrations to get next version number
find src/main/resources/db/migration -name "V*.sql" | sort -V | tail -5

# Find related entity changes
git diff --name-only HEAD -- '*.java' | grep -i "entity\|model\|domain"
```

2. Determine the next migration version:
   - Find the highest version number in `src/main/resources/db/migration/`
   - Increment by 1 for the next migration
   - Format: `V{number}__{description}.sql` -- two underscores, snake_case description

3. Ask the user what schema change is needed if not obvious from context.

4. Create the migration file following these rules:

### MySQL Migration Rules

```sql
-- File: V{N}__description.sql

-- Create table
CREATE TABLE IF NOT EXISTS orders (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT UNSIGNED NOT NULL,
    status      ENUM('PENDING','CONFIRMED','SHIPPED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    total_amount DECIMAL(10,2) NOT NULL,
    created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at  DATETIME(3) NULL,
    INDEX idx_orders_user_id (user_id),
    INDEX idx_orders_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Add column (always provide DEFAULT or handle nullability)
ALTER TABLE users ADD COLUMN phone_number VARCHAR(20) NULL AFTER email;

-- NEVER: DROP TABLE or DROP COLUMN without backward-compatibility strategy
-- NEVER: ALTER existing NOT NULL column without DEFAULT
```

### PostgreSQL Migration Rules

```sql
-- File: V{N}__description.sql

-- Create table
CREATE TABLE IF NOT EXISTS orders (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL,
    status      VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    total_amount NUMERIC(10,2) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);

-- CONCURRENT index (avoid table lock in production)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);

-- Add column (ALWAYS with DEFAULT to avoid table rewrite)
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number VARCHAR(20);

-- NEVER: CREATE INDEX without CONCURRENTLY for large tables (locks table)
-- NEVER: ALTER COLUMN type that requires table rewrite without maintenance window
```

5. Validate the migration:

```bash
# Run Flyway validate
./gradlew flywayValidate 2>/dev/null || ./mvnw flyway:validate 2>/dev/null

# Check migration info
./gradlew flywayInfo 2>/dev/null || ./mvnw flyway:info 2>/dev/null

# Compile check after entity changes
./gradlew compileJava 2>/dev/null || ./mvnw compile 2>/dev/null
```

6. Safety checklist before finalizing:

**CRITICAL checks:**
- [ ] Migration is forward-only
- [ ] Adding NOT NULL column? Has DEFAULT value or populates data first
- [ ] Dropping column? Confirmed code no longer references it
- [ ] Large table index? Uses CONCURRENTLY (PostgreSQL) or ALGORITHM=INPLACE (MySQL 8)
- [ ] Migration filename has double underscore: `V3__add_column.sql`
- [ ] No Java-side changes needed for the new column/table?

7. Suggest corresponding entity update if needed:

```java
// If adding 'phone_number' column to users table, update User entity:
@Column(name = "phone_number")
private String phoneNumber;
```

## Output

```
Migration created: src/main/resources/db/migration/V{N}__{description}.sql

SQL:
{show the created SQL}

Validation: {PASS / FAIL with reason}

Entity changes needed:
{List any entity fields that should be added/modified}
```
