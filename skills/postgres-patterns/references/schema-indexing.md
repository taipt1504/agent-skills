# Schema Design & Indexing — PostgreSQL 15+

---

## Naming Conventions

- Tables: `snake_case`, **plural** (`orders`, `order_items`, `users`)
- Columns: `snake_case`, **singular** (`user_id`, `created_at`, `total_amount`)
- Indexes: `idx_{table}_{columns}` (`idx_orders_user_status`)
- Constraints: `fk_{table}_{referenced_table}`, `uq_{table}_{column}`, `chk_{table}_{column}`
- Sequences: `{table}_{column}_seq` (auto-named when using `GENERATED ALWAYS AS IDENTITY`)

---

## Data Types — Best Choices

| Use Case | Recommended Type | Avoid | Notes |
|----------|-----------------|-------|-------|
| Surrogate PK | `bigint GENERATED ALWAYS AS IDENTITY` | `SERIAL`, `BIGSERIAL` | `IDENTITY` is SQL-standard; `SERIAL` is legacy PostgreSQL shorthand |
| UUID (distributed) | `uuid` | Random UUID as PK | `gen_random_uuid()` (pg 13+); or UUIDv7 for time-ordered insert performance |
| Strings | `text` | `varchar(255)` | Stored identically; `varchar(n)` only when length enforcement is needed |
| Currency | `numeric(10,2)` | `float`, `double precision` | Binary floating-point is inexact |
| Status / state | `text` + `CHECK` constraint or `ENUM` type | `int` codes | Prefer `text` + `CHECK` for easy ALTER; `ENUM` types are immutable without DDL |
| Boolean | `boolean` | `tinyint`, `varchar` | Native PostgreSQL type |
| Timestamps | `timestamptz` | `timestamp` | Always store with timezone; `timestamp` silently discards TZ info |
| JSON | `jsonb` | `json` | `jsonb` is indexed and queryable; `json` is stored as text |
| Arrays | `integer[]`, `text[]` | Separate join table (for small, fixed sets) | Use for short lists; join tables for variable-length relationships |
| Full-text | `tsvector` (stored) | `text` scanned with `LIKE` | Pre-compute with generated column + GIN index |
| IP addresses | `inet` | `varchar` | Built-in network functions |

---

## DDL Template

PostgreSQL encoding is set at the database level, not per table — no charset clause needed.

```sql
CREATE TABLE orders (
    id           bigint          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      bigint          NOT NULL,
    status       text            NOT NULL DEFAULT 'PENDING',
    total_amount numeric(10,2)   NOT NULL,
    note         text            NULL,
    metadata     jsonb           NULL DEFAULT '{}',
    created_at   timestamptz     NOT NULL DEFAULT now(),
    updated_at   timestamptz     NOT NULL DEFAULT now(),
    deleted_at   timestamptz     NULL,
    CONSTRAINT fk_orders_users  FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_orders_status CHECK (status IN ('PENDING', 'CONFIRMED', 'SHIPPED', 'CANCELLED')),
    CONSTRAINT chk_orders_amount CHECK (total_amount >= 0)
);

-- Indexes — always index FK columns
CREATE INDEX idx_orders_user_id  ON orders (user_id);
CREATE INDEX idx_orders_status   ON orders (status);
CREATE INDEX idx_orders_created  ON orders (created_at DESC);
CREATE INDEX idx_orders_deleted  ON orders (deleted_at) WHERE deleted_at IS NOT NULL;
```

---

## Soft Deletes

```sql
-- Add deleted_at column
ALTER TABLE users ADD COLUMN deleted_at timestamptz NULL;
CREATE INDEX idx_users_deleted_at ON users (deleted_at) WHERE deleted_at IS NOT NULL;

-- Application queries — always filter
SELECT id, email FROM users WHERE deleted_at IS NULL AND status = 'ACTIVE';
```

JPA side — see [jpa-hibernate.md](jpa-hibernate.md) for `@SQLRestriction`.

---

## Indexing Strategy

### Composite Index — Column Order Rule

1. **Equality predicates** first, highest cardinality first
2. **Range predicates** after equality columns
3. **ORDER BY** columns last (matching sort direction to avoid filesort)

```sql
-- Query: WHERE user_id = ? AND status = ? ORDER BY created_at DESC
CREATE INDEX idx_orders_user_status_created ON orders (user_id, status, created_at DESC);

-- ❌ Low-cardinality column first — optimizer skips most of index
CREATE INDEX idx_orders_status_user ON orders (status, user_id);
```

### Covering Index — PostgreSQL INCLUDE Syntax

PostgreSQL **supports** `INCLUDE` — columns in `INCLUDE` are stored in leaf pages but not the sort key, keeping the index compact.

```sql
-- Query: SELECT id, status, total_amount FROM orders WHERE user_id = ?
-- INCLUDE adds status and total_amount to leaf pages → "Index Only Scan" (no heap fetch)
CREATE INDEX idx_orders_user_covering
    ON orders (user_id)
    INCLUDE (status, total_amount);

-- Alternative: all columns in key (PostgreSQL also supports this but INCLUDE is preferred)
-- ON orders (user_id, status, total_amount)  -- status/total_amount affect sort key unnecessarily
```

### Partial Index

Only index rows matching a predicate — smaller index, faster maintenance:

```sql
-- Index only active (non-deleted) users on email
CREATE UNIQUE INDEX idx_users_email_active ON users (email) WHERE deleted_at IS NULL;

-- Index only pending orders (minority of rows)
CREATE INDEX idx_orders_pending ON orders (created_at DESC) WHERE status = 'PENDING';
```

### GIN Index — JSONB and Full-Text

```sql
-- JSONB containment queries
CREATE INDEX idx_orders_metadata ON orders USING gin (metadata);
-- Supports: WHERE metadata @> '{"channel": "mobile"}'

-- Full-text search with generated tsvector
ALTER TABLE articles ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, ''))) STORED;
CREATE INDEX idx_articles_search ON articles USING gin (search_vector);
-- Query: WHERE search_vector @@ plainto_tsquery('english', 'spring reactive')
```

### Generated Column for Expression Index

```sql
-- Index on normalized email (no function index overhead)
ALTER TABLE users ADD COLUMN email_normalized text
    GENERATED ALWAYS AS (lower(trim(email))) STORED;
CREATE UNIQUE INDEX idx_users_email_norm ON users (email_normalized);

-- Query
SELECT id FROM users WHERE email_normalized = lower(trim($1)) AND deleted_at IS NULL;
```

### BRIN Index — Time-Series Append-Only Data

```sql
-- BRIN records min/max per block — tiny index for physically ordered data
CREATE INDEX idx_events_created_brin ON events USING brin (created_at)
    WITH (pages_per_range = 128);
-- Effective only when rows are inserted in timestamp order (typical for events/logs)
```

---

## EXPLAIN — Understanding Output

```sql
-- ANALYZE runs the query and reports actual execution; BUFFERS shows cache hits
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.id, o.status, u.email
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.status = 'PENDING' AND o.created_at > now() - interval '7 days';
```

Key node types:

| Node | Meaning | Action |
|------|---------|--------|
| `Seq Scan` | Full table scan | Add or fix index |
| `Index Scan` | Uses index + heap fetch | Usually good; check filter |
| `Index Only Scan` | Covering index — no heap fetch | Best |
| `Bitmap Heap Scan` | Multi-index merge | OK for low-selectivity |
| `Hash Join` / `Merge Join` | Join strategies | Hash: large tables; Merge: sorted inputs |
| `Sort` | Explicit sort step | Add index on ORDER BY columns |

Key to watch:
- `rows=N (actual)` vs `rows=M (estimated)` — large gap → run `ANALYZE table_name` to refresh statistics
- `Buffers: shared hit=N read=M` — low hit rate (many reads) → table not cached, consider `pg_prewarm`
- `execution time` — total wall clock; compare to `planning time` (high planning = complex query or stale stats)

---

## UPSERT

```sql
-- ON CONFLICT DO UPDATE
INSERT INTO user_preferences (user_id, key, value)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, key)
DO UPDATE SET
    value      = EXCLUDED.value,
    updated_at = now();

-- ON CONFLICT DO NOTHING (idempotent insert)
INSERT INTO event_log (event_id, processed_at)
VALUES ($1, now())
ON CONFLICT (event_id) DO NOTHING;
```

---

## Keyset (Cursor) Pagination

`OFFSET N` forces PostgreSQL to read and discard N rows — O(n). Keyset anchors on the last-seen value — O(1).

```sql
-- First page
SELECT id, name, created_at
FROM products
WHERE deleted_at IS NULL
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- Next page — pass last row's (created_at, id) as cursor
SELECT id, name, created_at
FROM products
WHERE deleted_at IS NULL
  AND (created_at, id) < ($last_created_at, $last_id)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- Required composite index for O(log n) execution
CREATE INDEX idx_products_cursor ON products (created_at DESC, id DESC) WHERE deleted_at IS NULL;
```

---

## Queue Processing (SKIP LOCKED)

```sql
-- Atomic dequeue — safe under concurrent workers, no double-processing
UPDATE jobs
SET status = 'processing', started_at = now()
WHERE id = (
    SELECT id FROM jobs
    WHERE status = 'pending'
    ORDER BY created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED
)
RETURNING id, payload, created_at;  -- Explicit columns, never RETURNING *
```

---

## Row Level Security (Spring Boot Pattern)

> **Note**: `auth.uid()` is a Supabase extension — not available in standard PostgreSQL / Spring Boot.
> Spring Boot passes the current user via `SET LOCAL` within each transaction.

```sql
-- Enable RLS on table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;  -- Apply even to table owner

-- Policy using current_setting (set by application per request)
CREATE POLICY orders_tenant_isolation ON orders
    USING (user_id = (SELECT current_setting('app.current_user_id', true))::bigint);
```

Spring Boot side — set per request in a transaction-scoped interceptor:

```java
// In a HandlerInterceptor or reactive WebFilter — execute inside TX via TransactionalOperator
db.sql("SET LOCAL app.current_user_id = :uid")
  .bind("uid", userId.toString())
  .fetch().rowsUpdated();
```

---

## Diagnostic Queries

```sql
-- Unindexed foreign keys
SELECT conrelid::regclass AS table_name, a.attname AS column_name
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
  );

-- Slowest queries (requires pg_stat_statements extension)
SELECT query, round(mean_exec_time::numeric, 2) AS mean_ms, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Table bloat (dead tuples — trigger VACUUM)
SELECT relname, n_dead_tup, last_vacuum, last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;

-- Index usage (find unused indexes)
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY schemaname, tablename;
```
