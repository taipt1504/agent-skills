---
name: postgres-java-reactive-pro
description: Expert guidance for high-performance PostgreSQL with Java Reactive using R2DBC
triggers:
  - r2dbc postgresql
  - reactive postgres java
  - spring data r2dbc
  - high performance reactive database
  - /postgres-reactive
tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
references:
  - references/r2dbc-config.md
  - references/query-patterns.md
  - references/performance-tuning.md
scripts:
  - scripts/analyze-queries.py
  - scripts/benchmark.sh
---

# PostgreSQL Java Reactive Pro

Expert skill for building high-performance reactive applications with PostgreSQL and R2DBC in Java.

## Mục đích

Skill này giúp agent:

- Thiết kế và tối ưu hóa reactive database layer với R2DBC
- Viết high-performance queries cho PostgreSQL
- Apply best practices cho connection pooling, batching, và streaming
- Debug và troubleshoot performance issues

## Khi nào sử dụng

- Thiết kế reactive repository layer với Spring Data R2DBC
- Tối ưu hóa queries cho high throughput/low latency
- Configure connection pool cho production
- Implement batch operations và bulk inserts
- Stream large result sets efficiently
- Handle transactions trong reactive context

## Khi nào KHÔNG sử dụng

- Blocking JDBC applications (dùng Spring Data JDBC thay thế)
- Simple CRUD không cần optimize
- NoSQL databases
- Non-PostgreSQL databases (một số patterns có thể khác)

---

## Core Principles

### 1. Non-blocking Everything

R2DBC là fully non-blocking. KHÔNG BAO GIỜ:

- Block trong reactive chain (`.block()`, `.toFuture().get()`)
- Sử dụng blocking I/O trong reactive pipeline
- Mix blocking JDBC với R2DBC trong cùng transaction

```java
// BAD - blocking trong reactive chain
public User getUser(Long id) {
    return userRepository.findById(id).block(); // NEVER DO THIS
}

// GOOD - keep it reactive
public Mono<User> getUser(Long id) {
    return userRepository.findById(id);
}
```

### 2. Backpressure-aware

Luôn xem xét backpressure khi làm việc với large datasets:

```java
// GOOD - streaming với backpressure
public Flux<User> getAllUsers() {
    return userRepository.findAll()
        .limitRate(100); // Control flow rate
}

// GOOD - batch processing với controlled concurrency
public Flux<User> processUsers() {
    return userRepository.findAll()
        .buffer(50)
        .flatMap(batch -> processBatch(batch), 4); // Max 4 concurrent batches
}
```

### 3. Connection Pool Optimization

```java
@Configuration
public class R2dbcConfig extends AbstractR2dbcConfiguration {

    @Override
    public ConnectionFactory connectionFactory() {
        PostgresqlConnectionConfiguration config = PostgresqlConnectionConfiguration.builder()
            .host("localhost")
            .port(5432)
            .database("mydb")
            .username("user")
            .password("password")
            // Performance settings
            .preparedStatementCacheQueries(256)  // Cache prepared statements
            .build();

        PostgresqlConnectionFactory connectionFactory =
            new PostgresqlConnectionFactory(config);

        // Connection pooling với r2dbc-pool
        ConnectionPoolConfiguration poolConfig = ConnectionPoolConfiguration.builder()
            .connectionFactory(connectionFactory)
            .initialSize(10)                    // Initial connections
            .maxSize(50)                        // Max connections
            .maxIdleTime(Duration.ofMinutes(30))
            .maxLifeTime(Duration.ofHours(1))
            .maxAcquireTime(Duration.ofSeconds(5))
            .acquireRetry(3)
            .validationQuery("SELECT 1")
            .build();

        return new ConnectionPool(poolConfig);
    }
}
```

---

## High-Performance Query Patterns

### Pattern 1: Efficient Batch Inserts

```java
public Mono<Void> batchInsert(List<User> users) {
    return Flux.fromIterable(users)
        .buffer(1000)  // Batch size
        .flatMap(batch -> {
            String sql = "INSERT INTO users (name, email) VALUES " +
                batch.stream()
                    .map(u -> "('" + u.getName() + "', '" + u.getEmail() + "')")
                    .collect(Collectors.joining(", "));
            return databaseClient.sql(sql).then();
        }, 4)  // 4 concurrent batches
        .then();
}

// Better: Use COPY command for massive inserts
public Mono<Long> bulkInsertWithCopy(Publisher<User> users) {
    return Mono.from(connectionFactory.create())
        .flatMap(conn -> {
            PostgresqlConnection pgConn = (PostgresqlConnection) conn;
            return Flux.from(users)
                .map(this::toCopyData)
                .as(data -> pgConn.copyIn("COPY users (name, email) FROM STDIN"))
                .doFinally(signal -> conn.close().subscribe());
        });
}
```

### Pattern 2: Cursor-based Pagination (High Performance)

```java
// AVOID: Offset pagination for large datasets
// SLOW với large offsets
public Flux<User> getUsersOffset(int page, int size) {
    return userRepository.findAll()
        .skip((long) page * size)
        .take(size);
}

// BETTER: Cursor-based (keyset) pagination
public Flux<User> getUsersAfter(Long lastId, int size) {
    return databaseClient.sql(
        "SELECT * FROM users WHERE id > :lastId ORDER BY id LIMIT :size")
        .bind("lastId", lastId)
        .bind("size", size)
        .map(row -> mapToUser(row))
        .all();
}
```

### Pattern 3: Optimized Joins với Manual Mapping

```java
// Complex aggregates với single query
public Flux<OrderWithItems> getOrdersWithItems(Long userId) {
    String sql = """
        SELECT o.id as order_id, o.created_at, o.status,
               i.id as item_id, i.product_name, i.quantity, i.price
        FROM orders o
        LEFT JOIN order_items i ON o.id = i.order_id
        WHERE o.user_id = :userId
        ORDER BY o.id, i.id
        """;

    return databaseClient.sql(sql)
        .bind("userId", userId)
        .map(this::mapRow)
        .all()
        .bufferUntilChanged(row -> row.getOrderId())
        .map(this::aggregateOrder);
}
```

### Pattern 4: Parallel Query Execution

```java
public Mono<DashboardData> getDashboardData(Long userId) {
    Mono<UserStats> stats = getUserStats(userId);
    Mono<List<Order>> recentOrders = getRecentOrders(userId).collectList();
    Mono<Long> notificationCount = getNotificationCount(userId);

    // Execute in parallel
    return Mono.zip(stats, recentOrders, notificationCount)
        .map(tuple -> new DashboardData(
            tuple.getT1(),
            tuple.getT2(),
            tuple.getT3()
        ));
}
```

---

## PostgreSQL-Specific Optimizations

### 1. Use PostgreSQL Arrays

```java
// Efficient IN clause với ANY
public Flux<User> getUsersByIds(List<Long> ids) {
    return databaseClient.sql(
        "SELECT * FROM users WHERE id = ANY(:ids)")
        .bind("ids", ids.toArray(new Long[0]))
        .map(this::mapToUser)
        .all();
}
```

### 2. JSONB Operations

```java
// Query JSONB fields efficiently
public Flux<User> getUsersByMetadata(String key, String value) {
    return databaseClient.sql(
        "SELECT * FROM users WHERE metadata @> :json::jsonb")
        .bind("json", "{\"" + key + "\": \"" + value + "\"}")
        .map(this::mapToUser)
        .all();
}

// Index recommendation for JSONB
// CREATE INDEX idx_users_metadata ON users USING GIN (metadata);
```

### 3. Upsert với ON CONFLICT

```java
public Mono<User> upsertUser(User user) {
    return databaseClient.sql("""
        INSERT INTO users (id, name, email, updated_at)
        VALUES (:id, :name, :email, NOW())
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            email = EXCLUDED.email,
            updated_at = NOW()
        RETURNING *
        """)
        .bind("id", user.getId())
        .bind("name", user.getName())
        .bind("email", user.getEmail())
        .map(this::mapToUser)
        .one();
}
```

### 4. Partial Indexes

```sql
-- Index chỉ cho active users (nhỏ hơn, nhanh hơn)
CREATE INDEX idx_users_active_email ON users (email)
WHERE status = 'ACTIVE';

-- Index cho recent data
CREATE INDEX idx_orders_recent ON orders (created_at DESC)
WHERE created_at > NOW() - INTERVAL '30 days';
```

---

## Transaction Best Practices

### Reactive Transactions

```java
@Service
public class OrderService {

    private final TransactionalOperator transactionalOperator;

    public Mono<Order> createOrder(OrderRequest request) {
        return validateRequest(request)
            .flatMap(this::reserveInventory)
            .flatMap(this::createOrderRecord)
            .flatMap(this::processPayment)
            .as(transactionalOperator::transactional);
    }

    // Hoặc với annotation
    @Transactional
    public Mono<Order> createOrderAnnotated(OrderRequest request) {
        return validateRequest(request)
            .flatMap(this::reserveInventory)
            .flatMap(this::createOrderRecord);
    }
}
```

### Savepoints cho Partial Rollback

```java
public Mono<BatchResult> processBatchWithSavepoints(List<Item> items) {
    return Flux.fromIterable(items)
        .concatMap(item ->
            processItem(item)
                .onErrorResume(e -> {
                    log.warn("Failed to process item: {}", item.getId(), e);
                    return Mono.just(ItemResult.failed(item, e));
                })
        )
        .collectList()
        .map(BatchResult::new);
}
```

---

## Monitoring & Debugging

### Connection Pool Metrics

```java
@Configuration
public class R2dbcMetricsConfig {

    @Bean
    public ConnectionFactory connectionFactory(MeterRegistry registry) {
        ConnectionPool pool = createConnectionPool();

        // Register metrics
        Gauge.builder("r2dbc.pool.acquired", pool,
            p -> p.getMetrics().acquiredSize())
            .register(registry);

        Gauge.builder("r2dbc.pool.pending", pool,
            p -> p.getMetrics().pendingAcquireSize())
            .register(registry);

        return pool;
    }
}
```

### Query Logging

```yaml
# application.yml
logging:
  level:
    io.r2dbc.postgresql.QUERY: DEBUG # Log all queries
    io.r2dbc.postgresql.PARAM: DEBUG # Log parameters
    io.r2dbc.pool: DEBUG # Connection pool events
```

### Slow Query Detection

```java
public <T> Flux<T> executeWithTiming(String queryName, Flux<T> query) {
    return Flux.defer(() -> {
        long start = System.nanoTime();
        return query.doOnComplete(() -> {
            long duration = (System.nanoTime() - start) / 1_000_000;
            if (duration > 100) {
                log.warn("Slow query [{}]: {}ms", queryName, duration);
            }
        });
    });
}
```

---

## Common Anti-patterns

### 1. N+1 Query Problem

```java
// BAD - N+1 queries
public Flux<OrderDTO> getOrdersWithUser() {
    return orderRepository.findAll()
        .flatMap(order ->
            userRepository.findById(order.getUserId())
                .map(user -> new OrderDTO(order, user))
        );
}

// GOOD - Single query với join
public Flux<OrderDTO> getOrdersWithUserOptimized() {
    return databaseClient.sql("""
        SELECT o.*, u.name as user_name, u.email as user_email
        FROM orders o
        JOIN users u ON o.user_id = u.id
        """)
        .map(this::mapToOrderDTO)
        .all();
}
```

### 2. Unbounded Queries

```java
// BAD - có thể return millions of rows
public Flux<User> getAllUsers() {
    return userRepository.findAll();
}

// GOOD - always có limit
public Flux<User> getAllUsers(int limit) {
    return userRepository.findAll()
        .take(Math.min(limit, 10000));
}
```

### 3. Over-fetching

```java
// BAD - fetch tất cả columns
public Mono<User> getUserForDisplay(Long id) {
    return userRepository.findById(id);
}

// GOOD - chỉ fetch columns cần thiết
public Mono<UserSummary> getUserSummary(Long id) {
    return databaseClient.sql(
        "SELECT id, name, avatar_url FROM users WHERE id = :id")
        .bind("id", id)
        .map(row -> new UserSummary(
            row.get("id", Long.class),
            row.get("name", String.class),
            row.get("avatar_url", String.class)
        ))
        .one();
}
```

---

## Checklist trước Production

- [ ] Connection pool sized correctly (initialSize, maxSize)
- [ ] Prepared statement cache enabled
- [ ] All queries có proper indexes
- [ ] No N+1 queries
- [ ] Large result sets sử dụng streaming/pagination
- [ ] Transactions có proper timeout
- [ ] Metrics và logging configured
- [ ] Slow query threshold set
- [ ] Health check endpoint cho database connection
- [ ] Graceful shutdown handling

---

## References

Xem thêm chi tiết trong:

- `references/r2dbc-config.md` - Configuration chi tiết
- `references/query-patterns.md` - Query patterns và examples
- `references/performance-tuning.md` - Performance tuning guide

## Scripts

- `scripts/analyze-queries.py` - Phân tích slow queries từ PostgreSQL logs
- `scripts/benchmark.sh` - Benchmark connection pool settings
