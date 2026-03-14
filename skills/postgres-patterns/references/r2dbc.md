# R2DBC — Reactive PostgreSQL (Spring WebFlux)

Use this file when the service runs on **Spring WebFlux** (reactive / non-blocking).
Never mix blocking JDBC/JPA with a reactive pipeline — use R2DBC instead.

---

## Dependency

```gradle
// build.gradle
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-r2dbc'
    implementation 'org.postgresql:r2dbc-postgresql:1.0.5.RELEASE'  // Check Maven Central for latest
    runtimeOnly    'org.postgresql:postgresql'                        // Needed for Flyway (blocking at startup)
    testImplementation 'org.testcontainers:postgresql'
    testImplementation 'io.r2dbc:r2dbc-pool'
}
```

---

## application.yml — R2DBC Config

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME}?sslMode=require
    username: ${DB_USER}
    password: ${DB_PASS}
    pool:
      initial-size: 2
      max-size: 10                      # Size via HikariCP formula: vCPU*2+1 (SSD)
      max-idle-time: 10m
      max-create-connection-time: 30s
      validation-query: SELECT 1
  # Flyway requires JDBC — configure separately
  datasource:
    url: jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME}?sslmode=require
    username: ${DB_USER}
    password: ${DB_PASS}
    driver-class-name: org.postgresql.Driver
  flyway:
    enabled: true
```

---

## Entity / Domain Object for R2DBC

R2DBC does not use Hibernate or JPA annotations. Use Spring Data R2DBC annotations:

```java
// Spring Data R2DBC entity — NOT @Entity, NOT @SQLRestriction
@Table("orders")
public record OrderEntity(
    @Id Long id,            // null → INSERT; non-null → UPDATE
    Long userId,
    String status,
    BigDecimal totalAmount,
    String note,
    OffsetDateTime createdAt,
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

> `@SQLRestriction` is a Hibernate annotation — R2DBC ignores it.
> Add `AND deleted_at IS NULL` to every custom query manually.

---

## Reactive Repository

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

## R2dbcEntityTemplate — Programmatic CRUD

```java
@Service
@RequiredArgsConstructor
public class OrderReadRepository {

    private final R2dbcEntityTemplate template;

    public Mono<OrderEntity> findById(Long id) {
        return template.selectOne(
            Query.query(
                Criteria.where("id").is(id)
                        .and("deleted_at").isNull()
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
}
```

---

## DatabaseClient — Custom SQL

```java
@Service
@RequiredArgsConstructor
public class OrderQueryService {

    private final DatabaseClient db;

    // Parameterized query — never concatenate user input
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

    // Insert returning generated key
    public Mono<Long> insert(CreateOrderCommand cmd) {
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

    // UPSERT
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

### `@Transactional` on Reactive Methods

Spring detects reactive return types and uses `ReactiveTransactionManager` automatically:

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class OrderService {

    private final ReactiveOrderRepository orderRepo;
    private final InventoryRepository inventoryRepo;

    @Transactional    // readOnly = false for writes
    public Mono<OrderEntity> createOrder(CreateOrderCommand cmd) {
        return inventoryRepo.reserveStock(cmd.productId(), cmd.quantity())
            .then(orderRepo.save(OrderEntity.newPending(cmd.userId(), cmd.totalAmount())));
        // Both ops in one transaction — rolls back on any error
    }

    public Mono<OrderEntity> findById(Long id) {
        return orderRepo.findById(id)
            .switchIfEmpty(Mono.error(new OrderNotFoundException(id)));
    }
}
```

### `TransactionalOperator` — Programmatic Transactions

Use for lambdas, utility methods, or when `@Transactional` cannot be applied:

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

// Auto-configured if R2DBC is on classpath; explicit for clarity:
@Bean
TransactionalOperator transactionalOperator(ReactiveTransactionManager rtm) {
    return TransactionalOperator.create(rtm);
}
```

---

## Testing — R2DBC with Testcontainers

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
        // Flyway still needs JDBC datasource
        registry.add("spring.datasource.url",      postgres::getJdbcUrl);
        registry.add("spring.datasource.username",  postgres::getUsername);
        registry.add("spring.datasource.password",  postgres::getPassword);
    }

    @Autowired private R2dbcEntityTemplate template;
    @Autowired private ReactiveOrderRepository orderRepo;

    @BeforeEach
    void clean() {
        template.delete(OrderEntity.class).all().block();  // .block() OK in @BeforeEach (test thread)
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

---

## Common R2DBC Pitfalls

| Pitfall | Fix |
|---------|-----|
| `@SQLRestriction` on R2DBC entity | Ignored — add `AND deleted_at IS NULL` to every custom query |
| `@GeneratedValue` on R2DBC entity | Use `@Id` on nullable `Long`; null id → INSERT, Spring Data sets it from `RETURNING id` |
| Lazy loading associations | R2DBC has no lazy loading — fetch related data with separate reactive queries and combine via `zip` / `flatMap` |
| `@Transactional` on `void` return type | Must return `Mono<T>` or `Flux<T>` for reactive TX management |
| Missing `sslMode=require` in R2DBC URL | URL param is `sslMode` (camelCase) in R2DBC vs `sslmode` (lowercase) in JDBC |
| `timestamptz` columns mapped to `LocalDateTime` | Use `OffsetDateTime` or `ZonedDateTime` — `LocalDateTime` silently strips timezone |
