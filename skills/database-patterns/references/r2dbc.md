# R2DBC Patterns — Reactive Database Access

Use when the service runs on **Spring WebFlux** (reactive / non-blocking).
Never mix blocking JDBC/JPA with a reactive pipeline.

---

## Dependencies

### PostgreSQL

```gradle
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-r2dbc'
    implementation 'org.postgresql:r2dbc-postgresql:1.0.5.RELEASE'
    runtimeOnly    'org.postgresql:postgresql'       // Needed for Flyway (blocking at startup)
    testImplementation 'org.testcontainers:postgresql'
    testImplementation 'io.r2dbc:r2dbc-pool'
}
```

### MySQL

```gradle
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-r2dbc'
    implementation 'io.asyncer:r2dbc-mysql:1.2.0'   // Community driver
    runtimeOnly    'com.mysql:mysql-connector-j'     // Needed for Flyway
    testImplementation 'org.testcontainers:mysql'
    testImplementation 'io.r2dbc:r2dbc-pool'
}
```

---

## R2DBC Entity

R2DBC does not use JPA annotations. Use Spring Data R2DBC annotations:

```java
@Table("orders")
public record OrderEntity(
    @Id Long id,            // null -> INSERT; non-null -> UPDATE
    Long userId,
    String status,
    BigDecimal totalAmount,
    String note,
    OffsetDateTime createdAt,   // PostgreSQL: OffsetDateTime for timestamptz
    OffsetDateTime updatedAt,
    OffsetDateTime deletedAt
) {
    public static OrderEntity newPending(Long userId, BigDecimal amount) {
        return new OrderEntity(null, userId, "PENDING", amount, null,
                               OffsetDateTime.now(ZoneOffset.UTC),
                               OffsetDateTime.now(ZoneOffset.UTC), null);
    }
}
```

Notes:
- `@SQLRestriction` is a Hibernate annotation -- R2DBC ignores it. Add `AND deleted_at IS NULL` to every query manually.
- Use `OffsetDateTime` for PostgreSQL `timestamptz`. Use `LocalDateTime` only for MySQL `DATETIME`.
- `@GeneratedValue` is not supported -- `@Id` on nullable `Long` triggers INSERT.

---

## ReactiveCrudRepository

```java
public interface ReactiveOrderRepository extends ReactiveCrudRepository<OrderEntity, Long> {

    Flux<OrderEntity> findByUserIdAndDeletedAtIsNull(Long userId);

    @Query("SELECT * FROM orders WHERE user_id = :userId AND status = :status AND deleted_at IS NULL ORDER BY created_at DESC LIMIT :limit")
    Flux<OrderEntity> findByUserIdAndStatus(Long userId, String status, int limit);

    @Query("SELECT COUNT(*) FROM orders WHERE status = :status AND deleted_at IS NULL")
    Mono<Long> countByStatus(String status);
}
```

---

## R2dbcEntityTemplate -- Programmatic CRUD

```java
@Service
@RequiredArgsConstructor
public class OrderReadRepository {

    private final R2dbcEntityTemplate template;

    public Mono<OrderEntity> findById(Long id) {
        return template.selectOne(
            Query.query(
                Criteria.where("id").is(id).and("deleted_at").isNull()
            ),
            OrderEntity.class
        );
    }

    public Flux<OrderEntity> findByStatus(String status) {
        return template.select(
            Query.query(Criteria.where("status").is(status)
                                .and("deleted_at").isNull())
                 .sort(Sort.by(Sort.Direction.DESC, "created_at"))
                 .limit(100),
            OrderEntity.class
        );
    }

    public Mono<OrderEntity> save(OrderEntity entity) {
        return template.insert(entity);
    }

    public Mono<Long> countByStatus(String status) {
        return template.count(
            Query.query(Criteria.where("status").is(status).and("deleted_at").isNull()),
            OrderEntity.class
        );
    }
}
```

---

## DatabaseClient -- Custom SQL

```java
@Service
@RequiredArgsConstructor
public class OrderQueryService {

    private final DatabaseClient db;

    public Flux<OrderSummaryDto> findRecentByUser(Long userId, int limit) {
        return db.sql("""
                SELECT id, status, total_amount, created_at
                FROM orders
                WHERE user_id = :userId AND deleted_at IS NULL
                ORDER BY created_at DESC
                LIMIT :limit
                """)
            .bind("userId", userId)
            .bind("limit",  limit)
            .map(row -> new OrderSummaryDto(
                row.get("id",           Long.class),
                row.get("status",       String.class),
                row.get("total_amount", BigDecimal.class),
                row.get("created_at",  OffsetDateTime.class)
            ))
            .all();
    }

    // PostgreSQL -- INSERT RETURNING
    public Mono<Long> insertPostgres(CreateOrderCommand cmd) {
        return db.sql("""
                INSERT INTO orders (user_id, status, total_amount, created_at, updated_at)
                VALUES (:userId, 'PENDING', :amount, now(), now())
                RETURNING id
                """)
            .bind("userId", cmd.userId())
            .bind("amount", cmd.totalAmount())
            .map(row -> row.get("id", Long.class))
            .one();
    }

    // MySQL -- returnGeneratedValues (no RETURNING clause)
    public Mono<Long> insertMysql(CreateOrderCommand cmd) {
        return db.sql("INSERT INTO orders (user_id, status, total_amount, created_at) VALUES (:uid, 'PENDING', :amount, NOW(3))")
            .bind("uid",    cmd.userId())
            .bind("amount", cmd.totalAmount())
            .filter(s -> s.returnGeneratedValues("id"))
            .map(row -> row.get("id", Long.class))
            .one();
    }

    // PostgreSQL UPSERT
    public Mono<Void> upsertPreference(Long userId, String key, String value) {
        return db.sql("""
                INSERT INTO user_preferences (user_id, key, value, updated_at)
                VALUES (:userId, :key, :value, now())
                ON CONFLICT (user_id, key) DO UPDATE
                SET value = EXCLUDED.value, updated_at = now()
                """)
            .bind("userId", userId)
            .bind("key",    key)
            .bind("value",  value)
            .fetch().rowsUpdated().then();
    }
}
```

---

## Reactive Transactions

### @Transactional on Reactive Methods

Spring detects reactive return types and uses `ReactiveTransactionManager` automatically:

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class OrderService {

    private final ReactiveOrderRepository orderRepo;
    private final InventoryRepository inventoryRepo;

    @Transactional
    public Mono<OrderEntity> createOrder(CreateOrderCommand cmd) {
        return inventoryRepo.reserveStock(cmd.productId(), cmd.quantity())
            .then(orderRepo.save(OrderEntity.newPending(cmd.userId(), cmd.totalAmount())));
    }

    public Mono<OrderEntity> findById(Long id) {
        return orderRepo.findById(id)
            .switchIfEmpty(Mono.error(new OrderNotFoundException(id)));
    }
}
```

### TransactionalOperator -- Programmatic

Use for lambdas or when `@Transactional` cannot be applied:

```java
@Service
@RequiredArgsConstructor
public class PaymentService {

    private final TransactionalOperator txOperator;
    private final PaymentRepository paymentRepo;
    private final OrderRepository orderRepo;

    public Mono<Void> processPayment(PaymentCommand cmd) {
        Mono<Void> work = paymentRepo.record(cmd)
            .then(orderRepo.markPaid(cmd.orderId()))
            .then();
        return txOperator.transactional(work);
    }
}

@Bean
TransactionalOperator transactionalOperator(ReactiveTransactionManager rtm) {
    return TransactionalOperator.create(rtm);
}
```

---

## Pool Configuration

```yaml
spring:
  r2dbc:
    pool:
      initial-size: 2
      max-size: 10              # vCPU*2 + 1 (SSD)
      max-idle-time: 10m
      max-create-connection-time: 30s
      validation-query: SELECT 1
```

---

## Testing with Testcontainers

### PostgreSQL

```java
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class ReactiveOrderRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test")
        .withReuse(true);

    @DynamicPropertySource
    static void configure(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:postgresql://test:test@localhost:" + postgres.getMappedPort(5432) + "/testdb");
        registry.add("spring.r2dbc.username", () -> "test");
        registry.add("spring.r2dbc.password", () -> "test");
        registry.add("spring.datasource.url",      postgres::getJdbcUrl);
        registry.add("spring.datasource.username",  postgres::getUsername);
        registry.add("spring.datasource.password",  postgres::getPassword);
    }

    @Autowired private R2dbcEntityTemplate template;
    @Autowired private ReactiveOrderRepository orderRepo;

    @BeforeEach
    void clean() {
        template.delete(OrderEntity.class).all().block(); // .block() OK in test thread
    }

    @Test
    void shouldSaveAndFindOrder() {
        var entity = OrderEntity.newPending(1L, BigDecimal.TEN);

        StepVerifier.create(
            orderRepo.save(entity)
                .flatMap(saved -> orderRepo.findById(saved.id()))
        )
        .assertNext(found -> {
            assertThat(found.userId()).isEqualTo(1L);
            assertThat(found.status()).isEqualTo("PENDING");
            assertThat(found.totalAmount()).isEqualByComparingTo(BigDecimal.TEN);
        })
        .verifyComplete();
    }

    @Test
    void shouldFindByUserIdExcludingDeleted() {
        var active  = OrderEntity.newPending(1L, BigDecimal.TEN);
        var deleted = new OrderEntity(null, 1L, "PENDING", BigDecimal.ONE, null,
                                      OffsetDateTime.now(), OffsetDateTime.now(), OffsetDateTime.now());

        StepVerifier.create(
            orderRepo.save(active)
                .then(orderRepo.save(deleted))
                .thenMany(orderRepo.findByUserIdAndDeletedAtIsNull(1L))
        )
        .expectNextCount(1)
        .verifyComplete();
    }
}
```

### MySQL

```java
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class ReactiveOrderRepositoryTest {

    @Container
    static MySQLContainer<?> mysql = new MySQLContainer<>("mysql:8.0")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test")
        .withCommand("--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci")
        .withReuse(true);

    @DynamicPropertySource
    static void configure(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:mysql://test:test@localhost:" + mysql.getMappedPort(3306) + "/testdb");
        registry.add("spring.r2dbc.username", () -> "test");
        registry.add("spring.r2dbc.password", () -> "test");
        registry.add("spring.datasource.url",      mysql::getJdbcUrl);
        registry.add("spring.datasource.username",  mysql::getUsername);
        registry.add("spring.datasource.password",  mysql::getPassword);
    }

    @Autowired private R2dbcEntityTemplate template;

    @BeforeEach
    void clean() {
        template.delete(OrderEntity.class).all().block();
    }

    @Test
    void shouldSaveAndFindOrder() {
        var entity = OrderEntity.newPending(1L, BigDecimal.TEN);

        StepVerifier.create(
            template.insert(entity)
                .flatMap(saved -> template.selectOne(
                    Query.query(Criteria.where("id").is(saved.id())),
                    OrderEntity.class
                ))
        )
        .assertNext(found -> {
            assertThat(found.userId()).isEqualTo(1L);
            assertThat(found.status()).isEqualTo("PENDING");
        })
        .verifyComplete();
    }
}
```

---

## Common R2DBC Pitfalls

| Pitfall | Fix |
|---------|-----|
| `@SQLRestriction` on R2DBC entity | Ignored -- add `AND deleted_at IS NULL` manually |
| `@GeneratedValue` annotation | Not supported; use `@Id` on nullable `Long` |
| Lazy loading associations | R2DBC has no lazy loading -- fetch with separate queries + `zip`/`flatMap` |
| `@Transactional` on `void` method | Must return `Mono<T>` or `Flux<T>` for reactive TX |
| PG `sslMode` vs JDBC `sslmode` | R2DBC uses camelCase `sslMode=require` |
| MySQL missing `serverZoneId=UTC` | Causes datetime off-by-hours bugs |
| `timestamptz` mapped to `LocalDateTime` | Use `OffsetDateTime` -- `LocalDateTime` strips timezone |
