# Query Patterns Reference

## Repository Patterns

### Basic Repository

```java
public interface UserRepository extends ReactiveCrudRepository<User, Long> {

    Flux<User> findByStatus(String status);

    Mono<User> findByEmail(String email);

    @Query("SELECT * FROM users WHERE created_at > :since ORDER BY created_at DESC")
    Flux<User> findRecentUsers(@Param("since") LocalDateTime since);

    @Modifying
    @Query("UPDATE users SET status = :status WHERE id = :id")
    Mono<Integer> updateStatus(@Param("id") Long id, @Param("status") String status);
}
```

### Custom Repository Implementation

```java
public interface UserRepositoryCustom {
    Flux<User> searchUsers(UserSearchCriteria criteria);
    Mono<Long> bulkUpdateStatus(List<Long> ids, String status);
}

@Repository
public class UserRepositoryImpl implements UserRepositoryCustom {

    private final DatabaseClient databaseClient;

    @Override
    public Flux<User> searchUsers(UserSearchCriteria criteria) {
        StringBuilder sql = new StringBuilder("SELECT * FROM users WHERE 1=1");
        Map<String, Object> params = new HashMap<>();

        if (criteria.getName() != null) {
            sql.append(" AND name ILIKE :name");
            params.put("name", "%" + criteria.getName() + "%");
        }

        if (criteria.getStatus() != null) {
            sql.append(" AND status = :status");
            params.put("status", criteria.getStatus());
        }

        if (criteria.getCreatedAfter() != null) {
            sql.append(" AND created_at > :createdAfter");
            params.put("createdAfter", criteria.getCreatedAfter());
        }

        sql.append(" ORDER BY created_at DESC LIMIT :limit OFFSET :offset");
        params.put("limit", criteria.getLimit());
        params.put("offset", criteria.getOffset());

        DatabaseClient.GenericExecuteSpec spec = databaseClient.sql(sql.toString());
        for (Map.Entry<String, Object> entry : params.entrySet()) {
            spec = spec.bind(entry.getKey(), entry.getValue());
        }

        return spec.map(this::mapToUser).all();
    }

    @Override
    public Mono<Long> bulkUpdateStatus(List<Long> ids, String status) {
        return databaseClient.sql(
            "UPDATE users SET status = :status, updated_at = NOW() WHERE id = ANY(:ids)")
            .bind("status", status)
            .bind("ids", ids.toArray(new Long[0]))
            .fetch()
            .rowsUpdated();
    }
}
```

---

## Pagination Patterns

### Offset Pagination (Simple but slow for large offsets)

```java
public Flux<User> getUsersPage(int page, int size) {
    return databaseClient.sql(
        "SELECT * FROM users ORDER BY id LIMIT :size OFFSET :offset")
        .bind("size", size)
        .bind("offset", page * size)
        .map(this::mapToUser)
        .all();
}
```

### Keyset Pagination (Recommended for large datasets)

```java
public Flux<User> getUsersAfter(Long lastId, int size) {
    if (lastId == null) {
        return databaseClient.sql(
            "SELECT * FROM users ORDER BY id LIMIT :size")
            .bind("size", size)
            .map(this::mapToUser)
            .all();
    }

    return databaseClient.sql(
        "SELECT * FROM users WHERE id > :lastId ORDER BY id LIMIT :size")
        .bind("lastId", lastId)
        .bind("size", size)
        .map(this::mapToUser)
        .all();
}

// Multi-column keyset
public Flux<User> getUsersAfterSorted(LocalDateTime lastCreatedAt, Long lastId, int size) {
    return databaseClient.sql("""
        SELECT * FROM users
        WHERE (created_at, id) > (:lastCreatedAt, :lastId)
        ORDER BY created_at DESC, id DESC
        LIMIT :size
        """)
        .bind("lastCreatedAt", lastCreatedAt)
        .bind("lastId", lastId)
        .bind("size", size)
        .map(this::mapToUser)
        .all();
}
```

### Reactive Page Response

```java
public record PageResponse<T>(
    List<T> content,
    long totalElements,
    int page,
    int size,
    boolean hasNext
) {}

public Mono<PageResponse<User>> getUsersPageResponse(int page, int size) {
    Mono<List<User>> content = getUsersPage(page, size).collectList();
    Mono<Long> total = databaseClient.sql("SELECT COUNT(*) FROM users")
        .map(row -> row.get(0, Long.class))
        .one();

    return Mono.zip(content, total)
        .map(tuple -> new PageResponse<>(
            tuple.getT1(),
            tuple.getT2(),
            page,
            size,
            (long) (page + 1) * size < tuple.getT2()
        ));
}
```

---

## Batch Operations

### Batch Insert

```java
public Mono<Void> batchInsert(List<User> users) {
    if (users.isEmpty()) return Mono.empty();

    return Flux.fromIterable(users)
        .buffer(500)  // Batch size
        .concatMap(batch -> {
            StringBuilder sql = new StringBuilder(
                "INSERT INTO users (name, email, status) VALUES ");

            List<Object> params = new ArrayList<>();
            for (int i = 0; i < batch.size(); i++) {
                if (i > 0) sql.append(", ");
                int base = i * 3;
                sql.append(String.format("($%d, $%d, $%d)", base + 1, base + 2, base + 3));
                params.add(batch.get(i).getName());
                params.add(batch.get(i).getEmail());
                params.add(batch.get(i).getStatus());
            }

            DatabaseClient.GenericExecuteSpec spec = databaseClient.sql(sql.toString());
            for (int i = 0; i < params.size(); i++) {
                spec = spec.bind(i, params.get(i));
            }

            return spec.then();
        })
        .then();
}
```

### Batch Upsert

```java
public Mono<Void> batchUpsert(List<User> users) {
    return Flux.fromIterable(users)
        .buffer(500)
        .concatMap(batch -> {
            StringBuilder sql = new StringBuilder("""
                INSERT INTO users (id, name, email, status, updated_at)
                VALUES
                """);

            List<Object> params = new ArrayList<>();
            for (int i = 0; i < batch.size(); i++) {
                if (i > 0) sql.append(", ");
                int base = i * 4;
                sql.append(String.format("($%d, $%d, $%d, $%d, NOW())",
                    base + 1, base + 2, base + 3, base + 4));
                params.add(batch.get(i).getId());
                params.add(batch.get(i).getName());
                params.add(batch.get(i).getEmail());
                params.add(batch.get(i).getStatus());
            }

            sql.append("""
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name,
                    email = EXCLUDED.email,
                    status = EXCLUDED.status,
                    updated_at = EXCLUDED.updated_at
                """);

            DatabaseClient.GenericExecuteSpec spec = databaseClient.sql(sql.toString());
            for (int i = 0; i < params.size(); i++) {
                spec = spec.bind(i, params.get(i));
            }

            return spec.then();
        })
        .then();
}
```

---

## Join Patterns

### One-to-Many Manual Join

```java
public Flux<OrderWithItems> getOrdersWithItems(Long userId) {
    return databaseClient.sql("""
        SELECT
            o.id as order_id,
            o.user_id,
            o.status as order_status,
            o.total_amount,
            o.created_at as order_created_at,
            i.id as item_id,
            i.product_name,
            i.quantity,
            i.unit_price
        FROM orders o
        LEFT JOIN order_items i ON o.id = i.order_id
        WHERE o.user_id = :userId
        ORDER BY o.created_at DESC, o.id, i.id
        """)
        .bind("userId", userId)
        .map((row, metadata) -> new OrderItemRow(
            row.get("order_id", Long.class),
            row.get("user_id", Long.class),
            row.get("order_status", String.class),
            row.get("total_amount", BigDecimal.class),
            row.get("order_created_at", LocalDateTime.class),
            row.get("item_id", Long.class),
            row.get("product_name", String.class),
            row.get("quantity", Integer.class),
            row.get("unit_price", BigDecimal.class)
        ))
        .all()
        .bufferUntilChanged(OrderItemRow::orderId)
        .map(this::aggregateOrder);
}

private OrderWithItems aggregateOrder(List<OrderItemRow> rows) {
    OrderItemRow first = rows.get(0);
    List<OrderItem> items = rows.stream()
        .filter(r -> r.itemId() != null)
        .map(r -> new OrderItem(r.itemId(), r.productName(), r.quantity(), r.unitPrice()))
        .toList();

    return new OrderWithItems(
        first.orderId(),
        first.userId(),
        first.orderStatus(),
        first.totalAmount(),
        first.orderCreatedAt(),
        items
    );
}
```

### Many-to-Many Join

```java
public Flux<UserWithRoles> getUsersWithRoles() {
    return databaseClient.sql("""
        SELECT
            u.id as user_id,
            u.name as user_name,
            u.email,
            r.id as role_id,
            r.name as role_name
        FROM users u
        LEFT JOIN user_roles ur ON u.id = ur.user_id
        LEFT JOIN roles r ON ur.role_id = r.id
        ORDER BY u.id, r.id
        """)
        .map(this::mapToUserRoleRow)
        .all()
        .bufferUntilChanged(UserRoleRow::userId)
        .map(this::aggregateUserWithRoles);
}
```

---

## Aggregation Patterns

### Stats Query

```java
public Mono<UserStats> getUserStats(Long userId) {
    return databaseClient.sql("""
        SELECT
            COUNT(*) as total_orders,
            COALESCE(SUM(total_amount), 0) as total_spent,
            COALESCE(AVG(total_amount), 0) as avg_order_value,
            MAX(created_at) as last_order_date
        FROM orders
        WHERE user_id = :userId AND status = 'COMPLETED'
        """)
        .bind("userId", userId)
        .map(row -> new UserStats(
            row.get("total_orders", Long.class),
            row.get("total_spent", BigDecimal.class),
            row.get("avg_order_value", BigDecimal.class),
            row.get("last_order_date", LocalDateTime.class)
        ))
        .one();
}
```

### Time Series Aggregation

```java
public Flux<DailyStats> getDailyStats(LocalDate from, LocalDate to) {
    return databaseClient.sql("""
        SELECT
            DATE_TRUNC('day', created_at)::date as date,
            COUNT(*) as order_count,
            SUM(total_amount) as revenue,
            COUNT(DISTINCT user_id) as unique_users
        FROM orders
        WHERE created_at >= :from AND created_at < :to
        GROUP BY DATE_TRUNC('day', created_at)
        ORDER BY date
        """)
        .bind("from", from.atStartOfDay())
        .bind("to", to.plusDays(1).atStartOfDay())
        .map(row -> new DailyStats(
            row.get("date", LocalDate.class),
            row.get("order_count", Long.class),
            row.get("revenue", BigDecimal.class),
            row.get("unique_users", Long.class)
        ))
        .all();
}
```

---

## Locking Patterns

### Optimistic Locking

```java
@Table("users")
public class User {
    @Id
    private Long id;

    @Version
    private Long version;

    private String name;
    // ...
}

// Usage
public Mono<User> updateUser(Long id, String newName) {
    return userRepository.findById(id)
        .flatMap(user -> {
            user.setName(newName);
            return userRepository.save(user);
        })
        .retryWhen(Retry.backoff(3, Duration.ofMillis(100))
            .filter(e -> e instanceof OptimisticLockingFailureException));
}
```

### Pessimistic Locking

```java
public Mono<User> updateUserWithLock(Long id, Function<User, User> updater) {
    return databaseClient.sql("SELECT * FROM users WHERE id = :id FOR UPDATE")
        .bind("id", id)
        .map(this::mapToUser)
        .one()
        .map(updater)
        .flatMap(userRepository::save);
}

// Skip locked rows (for job processing)
public Flux<Job> getUnprocessedJobs(int limit) {
    return databaseClient.sql("""
        SELECT * FROM jobs
        WHERE status = 'PENDING'
        ORDER BY created_at
        LIMIT :limit
        FOR UPDATE SKIP LOCKED
        """)
        .bind("limit", limit)
        .map(this::mapToJob)
        .all();
}
```
