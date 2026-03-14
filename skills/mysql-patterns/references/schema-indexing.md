# Schema Design & Indexing — MySQL 8.x

---

## Naming Conventions

- Tables: `snake_case`, **plural** (`orders`, `order_items`, `users`)
- Columns: `snake_case`, **singular** (`user_id`, `created_at`, `total_amount`)
- Indexes: `idx_{table}_{columns}` (`idx_orders_user_status`)
- Foreign keys: `fk_{table}_{referenced_table}` (`fk_order_items_orders`)

---

## Data Types — Best Choices

| Use Case | Recommended Type | Notes |
|----------|-----------------|-------|
| Surrogate PK | `BIGINT UNSIGNED AUTO_INCREMENT` | Avoid UUID as PK — causes B-tree fragmentation |
| UUID / GUID (storage) | `BINARY(16)` | Use `UUID_TO_BIN(UUID(), 1)` for time-ordered; `BIN_TO_UUID(id, 1)` to read |
| UUID (readability OK) | `VARCHAR(36)` | Larger index; acceptable for low-write tables |
| Currency / financial | `DECIMAL(10,2)` | Never `FLOAT` or `DOUBLE` — binary floating point is inexact |
| Status / state | `VARCHAR(20)` with CHECK or `ENUM(...)` | `ENUM` is compact; `VARCHAR` is easier to evolve — map to Java `enum` with `@Enumerated(STRING)` |
| Boolean | `TINYINT(1)` | MySQL has no native `BOOLEAN`; 0 = false, 1 = true |
| Timestamps | `DATETIME(3)` | Millisecond precision; store and query in UTC; avoid `TIMESTAMP` (2038 limit, implicit TZ conversion) |
| JSON data | `JSON` | MySQL 8+ native; use generated columns to index inside JSON |
| Long text | `TEXT` | For content > 65 535 chars; avoid putting in `WHERE` without prefix index |

---

## DDL Template — utf8mb4 Required

> **Rule**: Every `CREATE TABLE` must declare `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`.
> Omitting charset/collation risks mojibake, silent data truncation, and mixed-collation join errors.

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
    INDEX idx_orders_user_id  (user_id),
    INDEX idx_orders_status   (status),
    INDEX idx_orders_created  (created_at),
    INDEX idx_orders_deleted  (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## Soft Deletes

```sql
-- DDL: nullable deleted_at column
ALTER TABLE users
    ADD COLUMN deleted_at DATETIME(3) NULL DEFAULT NULL,
    ADD INDEX  idx_users_deleted_at (deleted_at);

-- Query pattern — always filter explicitly
SELECT id, email FROM users WHERE deleted_at IS NULL AND status = 'ACTIVE';
```

JPA side — see [jpa-hibernate.md](jpa-hibernate.md) for `@SQLRestriction`.

---

## Indexing Strategy

### Composite Index — Column Order Rule

Place columns in this order:
1. **Equality predicates** first (highest cardinality → lowest)
2. **Range predicates** after equality
3. **ORDER BY / GROUP BY** columns last (if direction matches)

```sql
-- Query: WHERE user_id = ? AND status = ? ORDER BY created_at DESC
-- ✅ Correct order: equality (user_id, status) then sort (created_at)
CREATE INDEX idx_orders_user_status_created
    ON orders (user_id, status, created_at DESC)
    USING BTREE;

-- ❌ Wrong: low-cardinality status first — optimizer skips most of index
CREATE INDEX idx_orders_status_user ON orders (status, user_id);
```

### Covering Index — MySQL Syntax (No INCLUDE)

MySQL B-tree indexes do **not** support `INCLUDE`. To create a covering index, list every needed column in the key itself.

```sql
-- Query: SELECT id, status, total_amount FROM orders WHERE user_id = ?
-- ✅ All three projected columns in the index → "Using index" (no table lookup)
CREATE INDEX idx_orders_user_covering
    ON orders (user_id, status, total_amount);

-- ❌ WRONG — MySQL does not support INCLUDE
-- ON orders (user_id) INCLUDE (status, total_amount);
```

### Generated (Virtual) Column for Expression Indexes

```sql
-- Index on UPPER(email) without changing application queries
ALTER TABLE users
    ADD COLUMN email_upper VARCHAR(255)
        GENERATED ALWAYS AS (UPPER(email)) VIRTUAL,
    ADD INDEX idx_users_email_upper (email_upper);

-- Query using the generated column (optimizer picks up automatically)
SELECT id FROM users WHERE UPPER(email) = UPPER('User@Example.com');
```

### Partial Index Workaround (MySQL has no native partial indexes)

MySQL does not support `WHERE` clause on indexes. Workaround: composite index + filter the leading column by the most common discriminator value.

```sql
-- Index only active orders: leading column limits scan to active rows
CREATE INDEX idx_orders_active_user
    ON orders (status, user_id, created_at)
    COMMENT 'Optimised for status=ACTIVE queries; prefix filters inactive';
```

### Invisible Indexes (Safe Testing — MySQL 8.0.23+)

```sql
-- Make an index invisible without dropping it — queries won't use it
ALTER TABLE orders ALTER INDEX idx_orders_status INVISIBLE;

-- Confirm optimizer skips it: run EXPLAIN — key should be NULL
EXPLAIN SELECT id FROM orders WHERE status = 'PENDING';

-- Re-enable after validating no regression
ALTER TABLE orders ALTER INDEX idx_orders_status VISIBLE;
```

---

## EXPLAIN — Understanding Output

Run `EXPLAIN` before shipping any non-trivial query:

```sql
EXPLAIN SELECT o.id, o.status, u.email
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.status = 'PENDING' AND o.created_at > '2024-01-01';
```

| `type` | Meaning | Action |
|--------|---------|--------|
| `ALL` | Full table scan | Add or fix index |
| `index` | Full index scan | May need more selective leading column |
| `range` | Index range scan | Usually acceptable |
| `ref` | Index non-unique lookup | Good |
| `eq_ref` | Unique index lookup (joins) | Best for joins |
| `const` | Single-row match (PK / unique) | Best |

Key `Extra` values:
- `Using index` — covering index, no table lookup (good)
- `Using filesort` — sort done in memory/disk (add index on ORDER BY columns)
- `Using temporary` — temp table used (refactor GROUP BY or add index)

### EXPLAIN ANALYZE — Actual vs Estimated Rows (MySQL 8.0.18+)

```sql
-- Shows actual row counts and execution time alongside estimates
EXPLAIN ANALYZE
SELECT o.id, SUM(oi.amount)
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status = 'CONFIRMED'
GROUP BY o.id;
-- Look for: estimated_rows vs actual_rows — large gaps indicate stale statistics
-- Fix stale stats: ANALYZE TABLE orders;
```

---

## MySQL 8.0 — CTEs and Window Functions

### Common Table Expressions

```sql
-- Recursive CTE: hierarchy traversal
WITH RECURSIVE category_tree AS (
    SELECT id, parent_id, name, 0 AS depth
    FROM categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.parent_id, c.name, ct.depth + 1
    FROM categories c
    JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT * FROM category_tree ORDER BY depth, name;
```

### Window Functions

```sql
-- Running total per user, ordered by date
SELECT
    id,
    user_id,
    total_amount,
    SUM(total_amount) OVER (
        PARTITION BY user_id
        ORDER BY created_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) AS recency_rank
FROM orders
WHERE deleted_at IS NULL;
```
