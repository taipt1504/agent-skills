# Performance Tuning Reference

## PostgreSQL Configuration for R2DBC

### postgresql.conf Recommendations

```ini
# Memory
shared_buffers = 256MB              # 25% of RAM for dedicated server
effective_cache_size = 768MB        # 75% of RAM
work_mem = 16MB                     # Per operation, be careful
maintenance_work_mem = 128MB        # For VACUUM, CREATE INDEX

# Connections
max_connections = 200               # Based on app needs
superuser_reserved_connections = 3

# WAL
wal_buffers = 16MB
checkpoint_completion_target = 0.9
max_wal_size = 2GB
min_wal_size = 1GB

# Query Planner
random_page_cost = 1.1              # For SSD (default 4.0 for HDD)
effective_io_concurrency = 200       # For SSD (default 1 for HDD)

# Parallelism
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4

# Logging (development)
log_min_duration_statement = 100    # Log queries > 100ms
log_statement = 'none'              # 'all' for debugging
```

---

## Index Strategies

### B-Tree Indexes (Default)

```sql
-- Primary key (auto-created)
-- Good for: =, <, >, <=, >=, BETWEEN, IN, ORDER BY

-- Single column
CREATE INDEX idx_users_email ON users (email);

-- Composite index (order matters!)
CREATE INDEX idx_orders_user_status ON orders (user_id, status);
-- Good for: WHERE user_id = ? AND status = ?
-- Good for: WHERE user_id = ?
-- NOT good for: WHERE status = ?

-- Covering index (includes all needed columns)
CREATE INDEX idx_orders_covering ON orders (user_id, status)
INCLUDE (total_amount, created_at);
-- Allows index-only scans
```

### Partial Indexes

```sql
-- Index only active users (smaller, faster)
CREATE INDEX idx_users_active_email ON users (email)
WHERE status = 'ACTIVE';

-- Index only recent orders
CREATE INDEX idx_orders_recent ON orders (created_at DESC)
WHERE created_at > NOW() - INTERVAL '30 days';

-- Index for soft deletes
CREATE INDEX idx_orders_not_deleted ON orders (user_id, created_at)
WHERE deleted_at IS NULL;
```

### Expression Indexes

```sql
-- Case-insensitive search
CREATE INDEX idx_users_email_lower ON users (LOWER(email));

-- Query: WHERE LOWER(email) = 'test@example.com'

-- Date part extraction
CREATE INDEX idx_orders_date ON orders (DATE(created_at));

-- Query: WHERE DATE(created_at) = '2024-01-15'
```

### GIN Indexes (Full-text, Arrays, JSONB)

```sql
-- JSONB containment
CREATE INDEX idx_users_metadata ON users USING GIN (metadata);
-- Query: WHERE metadata @> '{"type": "premium"}'

-- JSONB path operations
CREATE INDEX idx_users_metadata_path ON users USING GIN (metadata jsonb_path_ops);

-- Array containment
CREATE INDEX idx_posts_tags ON posts USING GIN (tags);
-- Query: WHERE tags @> ARRAY['java', 'reactive']

-- Full-text search
CREATE INDEX idx_posts_fts ON posts USING GIN (to_tsvector('english', title || ' ' || content));
```

### BRIN Indexes (Large sequential data)

```sql
-- Perfect for time-series data
CREATE INDEX idx_events_timestamp ON events USING BRIN (created_at);

-- Very small index, good for append-only tables
-- Less precise than B-tree, but much smaller
```

---

## Query Optimization

### EXPLAIN ANALYZE

```java
public Mono<String> explainQuery(String sql) {
    return databaseClient.sql("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + sql)
        .map(row -> row.get(0, String.class))
        .one();
}
```

### Common Query Issues

#### 1. Sequential Scan on Large Table

```sql
-- Problem
EXPLAIN SELECT * FROM orders WHERE status = 'PENDING';
-- Seq Scan on orders (cost=0.00..25000.00 rows=100 width=200)

-- Solution: Add index
CREATE INDEX idx_orders_status ON orders (status);
```

#### 2. Index Not Used

```sql
-- Problem: Function on indexed column
SELECT * FROM users WHERE LOWER(email) = 'test@test.com';
-- Won't use index on email

-- Solution: Expression index
CREATE INDEX idx_users_email_lower ON users (LOWER(email));
```

#### 3. Inefficient Join

```sql
-- Problem: Nested Loop on large tables
EXPLAIN SELECT * FROM orders o JOIN users u ON o.user_id = u.id;
-- Nested Loop (cost=...)

-- Solution: Ensure indexes exist
CREATE INDEX idx_orders_user_id ON orders (user_id);
-- Should use Hash Join or Merge Join
```

---

## R2DBC Performance Tuning

### Prepared Statement Cache

```java
PostgresqlConnectionConfiguration.builder()
    .preparedStatementCacheQueries(256)  // Cache up to 256 queries
    .build();
```

### Fetch Size (Streaming)

```java
// For large result sets
public Flux<User> streamAllUsers() {
    return databaseClient.sql("SELECT * FROM users")
        .map(this::mapToUser)
        .all()
        .limitRate(100);  // Backpressure: request 100 at a time
}
```

### Batch Size Optimization

```java
// Test different batch sizes
public Mono<Duration> benchmarkBatchSize(List<User> users, int batchSize) {
    long start = System.nanoTime();

    return Flux.fromIterable(users)
        .buffer(batchSize)
        .concatMap(this::insertBatch)
        .then()
        .thenReturn(Duration.ofNanos(System.nanoTime() - start));
}

// Typical optimal: 500-2000 rows per batch
```

### Connection Pool Monitoring

```java
@Scheduled(fixedRate = 60000)
public void logPoolMetrics() {
    if (connectionFactory instanceof ConnectionPool pool) {
        PoolMetrics metrics = pool.getMetrics().orElse(null);
        if (metrics != null) {
            log.info("Pool stats - acquired: {}, pending: {}, idle: {}, allocated: {}",
                metrics.acquiredSize(),
                metrics.pendingAcquireSize(),
                metrics.idleSize(),
                metrics.allocatedSize());

            // Alert if pool exhausted
            if (metrics.pendingAcquireSize() > 10) {
                log.warn("Connection pool exhausted! Pending: {}",
                    metrics.pendingAcquireSize());
            }
        }
    }
}
```

---

## Common Performance Anti-patterns

### 1. SELECT *

```java
// BAD
public Flux<User> getAllUsers() {
    return databaseClient.sql("SELECT * FROM users").map(this::mapToUser).all();
}

// GOOD - select only needed columns
public Flux<UserSummary> getUserSummaries() {
    return databaseClient.sql("SELECT id, name, email FROM users")
        .map(this::mapToSummary)
        .all();
}
```

### 2. N+1 Queries

```java
// BAD - N+1
public Flux<OrderDTO> getOrders() {
    return orderRepository.findAll()
        .flatMap(order ->
            userRepository.findById(order.getUserId())
                .map(user -> new OrderDTO(order, user))
        );
}

// GOOD - Single query with JOIN
public Flux<OrderDTO> getOrdersOptimized() {
    return databaseClient.sql("""
        SELECT o.*, u.name as user_name, u.email as user_email
        FROM orders o
        JOIN users u ON o.user_id = u.id
        """)
        .map(this::mapToOrderDTO)
        .all();
}
```

### 3. Unbounded Queries

```java
// BAD - can return millions
public Flux<Event> getEvents() {
    return eventRepository.findAll();
}

// GOOD - always limit
public Flux<Event> getEvents(int limit) {
    return eventRepository.findAll().take(Math.min(limit, 10000));
}
```

### 4. Missing Transaction Boundaries

```java
// BAD - multiple separate transactions
public Mono<Void> transferMoney(Long from, Long to, BigDecimal amount) {
    return accountRepository.debit(from, amount)
        .then(accountRepository.credit(to, amount));
}

// GOOD - single transaction
@Transactional
public Mono<Void> transferMoney(Long from, Long to, BigDecimal amount) {
    return accountRepository.debit(from, amount)
        .then(accountRepository.credit(to, amount));
}
```

---

## Monitoring Queries

### Slow Query Log

```sql
-- Enable in postgresql.conf
log_min_duration_statement = 100  -- Log queries taking > 100ms

-- Or per-session
SET log_min_duration_statement = 50;
```

### pg_stat_statements

```sql
-- Enable extension
CREATE EXTENSION pg_stat_statements;

-- Top 10 slowest queries
SELECT
    calls,
    mean_exec_time::numeric(10,2) as avg_ms,
    total_exec_time::numeric(10,2) as total_ms,
    rows,
    query
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Most called queries
SELECT
    calls,
    mean_exec_time::numeric(10,2) as avg_ms,
    query
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;
```

### Active Queries

```sql
SELECT
    pid,
    NOW() - query_start AS duration,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;
```

### Lock Monitoring

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocking.pid AS blocking_pid,
    blocked.query AS blocked_query,
    blocking.query AS blocking_query
FROM pg_locks blocked
JOIN pg_locks blocking ON blocking.locktype = blocked.locktype
    AND blocking.database = blocked.database
    AND blocking.relation = blocked.relation
    AND blocking.pid != blocked.pid
JOIN pg_stat_activity blocked_act ON blocked_act.pid = blocked.pid
JOIN pg_stat_activity blocking_act ON blocking_act.pid = blocking.pid
WHERE NOT blocked.granted;
```

---

## Benchmarking

### Quick Benchmark

```java
@Test
public void benchmarkQueryPerformance() {
    int iterations = 1000;
    long start = System.nanoTime();

    Flux.range(0, iterations)
        .flatMap(i -> userRepository.findById((long) (i % 100) + 1))
        .blockLast();

    long duration = System.nanoTime() - start;
    double avgMs = duration / 1_000_000.0 / iterations;

    System.out.printf("Average query time: %.2f ms%n", avgMs);
    assertThat(avgMs).isLessThan(10.0);
}
```

### Throughput Test

```java
@Test
public void benchmarkThroughput() {
    int requests = 10000;
    int concurrency = 100;

    long start = System.nanoTime();

    Flux.range(0, requests)
        .flatMap(i -> userRepository.findById((long) (i % 100) + 1), concurrency)
        .blockLast();

    long durationMs = (System.nanoTime() - start) / 1_000_000;
    double rps = (double) requests / durationMs * 1000;

    System.out.printf("Throughput: %.0f requests/second%n", rps);
}
```
