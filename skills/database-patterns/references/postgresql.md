# PostgreSQL Patterns — Schema, Indexing, Config

---

## Data Types

| Use Case | Type | Notes |
|----------|------|-------|
| Surrogate PK | `bigint GENERATED ALWAYS AS IDENTITY` | Not `SERIAL`; SQL-standard |
| UUID | `uuid` | `gen_random_uuid()` (pg 13+); UUIDv7 for insert order |
| Strings | `text` | Stored identically to `varchar(n)` |
| Currency | `numeric(10,2)` | Never `float`/`double precision` |
| Timestamps | `timestamptz` | Always TZ-aware; `timestamp` silently drops TZ |
| JSON | `jsonb` | Indexed + queryable; not `json` |
| Boolean | `boolean` | Native type |
| Full-text | `tsvector` (stored) | Generated column + GIN index |

---

## DDL Template

```sql
CREATE TABLE orders (
    id           bigint          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      bigint          NOT NULL,
    status       text            NOT NULL DEFAULT 'PENDING',
    total_amount numeric(10,2)   NOT NULL,
    metadata     jsonb           NULL DEFAULT '{}',
    created_at   timestamptz     NOT NULL DEFAULT now(),
    updated_at   timestamptz     NOT NULL DEFAULT now(),
    deleted_at   timestamptz     NULL,
    CONSTRAINT fk_orders_users FOREIGN KEY (user_id) REFERENCES users (id),
    CONSTRAINT chk_orders_status CHECK (status IN ('PENDING','CONFIRMED','SHIPPED','CANCELLED')),
    CONSTRAINT chk_orders_amount CHECK (total_amount >= 0)
);

CREATE INDEX idx_orders_user_id ON orders (user_id);
CREATE INDEX idx_orders_status  ON orders (status);
CREATE INDEX idx_orders_created ON orders (created_at DESC);
CREATE INDEX idx_orders_deleted ON orders (deleted_at) WHERE deleted_at IS NOT NULL;
```

---

## Indexing Strategy

### B-tree (Default)

```sql
-- Composite: equality first, range second, ORDER BY last
CREATE INDEX idx_orders_user_status_created ON orders (user_id, status, created_at DESC);
```

### Covering Index (INCLUDE)

```sql
-- Adds columns to leaf pages without affecting sort key -> Index Only Scan
CREATE INDEX idx_orders_user_covering
    ON orders (user_id) INCLUDE (status, total_amount);
```

### Partial Index

```sql
-- Only index active rows -> smaller, faster
CREATE UNIQUE INDEX idx_users_email_active ON users (email) WHERE deleted_at IS NULL;
CREATE INDEX idx_orders_pending ON orders (created_at DESC) WHERE status = 'PENDING';
```

### GIN Index (JSONB + Full-Text)

```sql
CREATE INDEX idx_orders_metadata ON orders USING gin (metadata);
-- Supports: WHERE metadata @> '{"channel": "mobile"}'

-- Full-text with generated tsvector
ALTER TABLE articles ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(body,''))) STORED;
CREATE INDEX idx_articles_search ON articles USING gin (search_vector);
```

### GiST Index (Geometry)

```sql
CREATE INDEX idx_locations_geom ON locations USING gist (geom);
```

### BRIN Index (Time-Series)

```sql
-- Tiny index for physically ordered append-only data
CREATE INDEX idx_events_created_brin ON events USING brin (created_at)
    WITH (pages_per_range = 128);
```

### Generated Column for Expression Index

```sql
ALTER TABLE users ADD COLUMN email_normalized text
    GENERATED ALWAYS AS (lower(trim(email))) STORED;
CREATE UNIQUE INDEX idx_users_email_norm ON users (email_normalized);
```

---

## UPSERT

```sql
INSERT INTO user_preferences (user_id, key, value)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, key)
DO UPDATE SET value = EXCLUDED.value, updated_at = now();

-- Idempotent insert
INSERT INTO event_log (event_id, processed_at)
VALUES ($1, now())
ON CONFLICT (event_id) DO NOTHING;
```

---

## Keyset (Cursor) Pagination

`OFFSET N` is O(n). Keyset is O(log n).

```sql
-- First page
SELECT id, name, created_at FROM products
WHERE deleted_at IS NULL
ORDER BY created_at DESC, id DESC LIMIT 20;

-- Next page
SELECT id, name, created_at FROM products
WHERE deleted_at IS NULL
  AND (created_at, id) < ($last_created_at, $last_id)
ORDER BY created_at DESC, id DESC LIMIT 20;

-- Required index
CREATE INDEX idx_products_cursor ON products (created_at DESC, id DESC)
    WHERE deleted_at IS NULL;
```

---

## SKIP LOCKED (Queue Processing)

```sql
UPDATE jobs SET status = 'processing', started_at = now()
WHERE id = (
    SELECT id FROM jobs WHERE status = 'pending'
    ORDER BY created_at LIMIT 1
    FOR UPDATE SKIP LOCKED
)
RETURNING id, payload, created_at;
```

---

## Row Level Security (Spring Boot)

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;

CREATE POLICY orders_tenant_isolation ON orders
    USING (user_id = (SELECT current_setting('app.current_user_id', true))::bigint);
```

Spring side -- set per request in TX:

```java
db.sql("SET LOCAL app.current_user_id = :uid")
  .bind("uid", userId.toString())
  .fetch().rowsUpdated();
```

---

## JPA Config (PostgreSQL)

```yaml
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require
    driver-class-name: org.postgresql.Driver
  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
        default_batch_fetch_size: 20
        jdbc:
          batch_size: 100
          order_inserts: true
          order_updates: true
    open-in-view: false
```

Key: Use `@GeneratedValue(strategy = SEQUENCE)` + `@SequenceGenerator(allocationSize = 50)`.
Never use `IDENTITY` strategy -- it disables batch inserts.

```java
@Id
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "orders_id_seq")
@SequenceGenerator(name = "orders_id_seq", sequenceName = "orders_id_seq", allocationSize = 50)
private Long id;
```

DDL must match: `CREATE SEQUENCE orders_id_seq START 1 INCREMENT 50 NO CYCLE;`

---

## R2DBC Config (PostgreSQL)

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslMode=require
    username: ${DB_USER}
    password: ${DB_PASS}
    pool:
      initial-size: 2
      max-size: 10
      max-idle-time: 10m
      max-create-connection-time: 30s
      validation-query: SELECT 1
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require
    driver-class-name: org.postgresql.Driver
  flyway:
    enabled: true
```

Driver dependency: `org.postgresql:r2dbc-postgresql`

Note: `sslMode` (camelCase) in R2DBC URL vs `sslmode` (lowercase) in JDBC URL.

---

## Pool Sizing

```
pool_size = (vCPU * 2) + effective_spindle_count
```

| Server | vCPU | Pool |
|--------|------|------|
| 2-vCPU SSD | 2 | 5 |
| 4-vCPU SSD | 4 | 9 |
| 8-vCPU SSD | 8 | 17 |

HikariCP config:

```yaml
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require&reWriteBatchedInserts=true
    hikari:
      pool-name: HikariPool-Main
      maximum-pool-size: 10
      minimum-idle: 2
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000
      keepalive-time: 60000
```

`reWriteBatchedInserts=true` enables PG-side INSERT batching.

### PgBouncer (Multi-Instance)

```ini
[pgbouncer]
pool_mode         = transaction
max_client_conn   = 1000
default_pool_size = 20
```

In transaction pooling mode, prepared statements are disabled.

### Server Tuning

```sql
ALTER SYSTEM SET max_connections = 100;
ALTER SYSTEM SET shared_buffers = '256MB';       -- 25% of RAM
ALTER SYSTEM SET work_mem = '4MB';               -- work_mem * max_connections * parallel_workers = memory
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';
ALTER SYSTEM SET statement_timeout = '30s';
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

---

## Flyway Config (PostgreSQL)

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false
    default-schema: public
    validate-on-migrate: true
    out-of-order: false
```

Migration header -- set search path (no charset needed):

```sql
SET search_path TO public;
```

---

## EXPLAIN

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.id, o.status FROM orders o WHERE o.status = 'PENDING';
```

| Node | Meaning |
|------|---------|
| `Seq Scan` | Full table scan -- add index |
| `Index Scan` | Uses index + heap fetch |
| `Index Only Scan` | Covering index -- best |
| `Bitmap Heap Scan` | Multi-index merge |

---

## Diagnostic Queries

```sql
-- Unindexed foreign keys
SELECT conrelid::regclass AS table_name, a.attname AS column_name
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
  );

-- Unused indexes
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes WHERE idx_scan = 0;

-- Table bloat
SELECT relname, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables WHERE n_dead_tup > 1000 ORDER BY n_dead_tup DESC;
```
