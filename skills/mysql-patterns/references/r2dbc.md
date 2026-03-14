# R2DBC — Reactive MySQL (Spring WebFlux)

Use this file when the service runs on **Spring WebFlux** (reactive / non-blocking).
Never mix blocking JDBC/JPA with a reactive pipeline — use R2DBC instead.

---

## Dependency

```gradle
// build.gradle
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-r2dbc'
    implementation 'io.asyncer:r2dbc-mysql:1.2.0'          // Community driver; check Maven Central for latest
    runtimeOnly    'com.mysql:mysql-connector-j'            // Needed for Flyway (still runs blocking at startup)
    testImplementation 'org.testcontainers:mysql'
    testImplementation 'io.r2dbc:r2dbc-pool'
}
```

---

## application.yml — R2DBC Config

```yaml
spring:
  r2dbc:
    url: r2dbc:mysql://${DB_HOST:localhost}:${DB_PORT:3306}/${DB_NAME}?serverZoneId=UTC&useUnicode=true&characterEncoding=UTF-8
    username: ${DB_USER}
    password: ${DB_PASS}
    pool:
      initial-size: 2
      max-size: 10                    # Size via HikariCP formula: vCPU*2+1 (SSD)
      max-idle-time: 10m
      max-create-connection-time: 30s
      validation-query: SELECT 1
  # Flyway uses JDBC datasource — configure separately
  datasource:
    url: jdbc:mysql://${DB_HOST:localhost}:${DB_PORT:3306}/${DB_NAME}?useUnicode=true&characterEncoding=UTF-8
    username: ${DB_USER}
    password: ${DB_PASS}
    driver-class-name: com.mysql.cj.jdbc.Driver
  flyway:
    enabled: true
```

---

## Reactive Repository

```java
// Entity — no @GeneratedValue(IDENTITY); use @Id + Spring Data inserts on null id
@Table("orders")
public record OrderEntity(
    @Id Long id,
    Long userId,
    String status,
    BigDecimal totalAmount,
    LocalDateTime createdAt,
    LocalDateTime updatedAt,
    LocalDateTime deletedAt
) {}

// Repository
public interface ReactiveOrderRepository extends ReactiveCrudRepository<OrderEntity, Long> {

    Flux<OrderEntity> findByUserIdAndDeletedAtIsNull(Long userId);

    @Query("SELECT * FROM orders WHERE user_id = :userId AND status = :status AND deleted_at IS NULL")
    Flux<OrderEntity> findByUserIdAndStatus(Long userId, String status);
}
```

---

## R2dbcEntityTemplate — Simple CRUD

```java
@Service
@RequiredArgsConstructor
public class OrderRepository {

    private final R2dbcEntityTemplate template;

    public Mono<OrderEntity> findById(Long id) {
        return template.selectOne(
            Query.query(Criteria.where("id").is(id).and("deleted_at").isNull()),
            OrderEntity.class
        );
    }

    public Mono<OrderEntity> save(OrderEntity order) {
        return template.insert(order);
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

## DatabaseClient — Custom SQL with Reactive Result Mapping

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
                row.get("created_at",  LocalDateTime.class)
            ))
            .all();
    }

    // Insert returning generated key
    public Mono<Long> insert(CreateOrderCommand cmd) {
        return db.sql("INSERT INTO orders (user_id, status, total_amount, created_at) VALUES (:uid, :status, :amount, NOW(3))")
            .bind("uid",    cmd.userId())
            .bind("status", "PENDING")
            .bind("amount", cmd.totalAmount())
            .filter(s -> s.returnGeneratedValues("id"))
            .map(row -> row.get("id", Long.class))
            .one();
    }
}
```

---

## Reactive Transactions

### `@Transactional` on Reactive Methods

Spring detects the reactive return type and uses `ReactiveTransactionManager` automatically.

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)   // Default read-only for Flux/Mono methods
public class OrderService {

    private final ReactiveOrderRepository orderRepo;
    private final InventoryRepository inventoryRepo;

    @Transactional    // readOnly = false for writes
    public Mono<OrderEntity> createOrder(CreateOrderCommand cmd) {
        return inventoryRepo.reserveStock(cmd.productId(), cmd.quantity())
            .then(orderRepo.save(OrderEntity.newOrder(cmd)));
        // Both operations in one transaction — rolls back on any error
    }
}
```

### `TransactionalOperator` — Programmatic Transactions

Use when you cannot annotate a method (e.g., lambdas, reactive utility methods).

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

// Bean configuration (auto-configured if R2DBC is on classpath, but explicit for clarity)
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
        // Flyway still needs JDBC datasource
        registry.add("spring.datasource.url",      mysql::getJdbcUrl);
        registry.add("spring.datasource.username",  mysql::getUsername);
        registry.add("spring.datasource.password",  mysql::getPassword);
    }

    @Autowired private R2dbcEntityTemplate template;

    @BeforeEach
    void clean() {
        template.delete(OrderEntity.class).all().block();  // .block() OK in @BeforeEach (test thread)
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
| `@GeneratedValue` annotation | Not fully supported in R2DBC; use `@Id` on nullable field — Spring Data sets it after insert |
| `@SQLRestriction` | R2DBC ignores Hibernate annotations — add `deleted_at IS NULL` to every custom query |
| Lazy loading associations | R2DBC has no lazy loading — fetch related data in separate reactive queries and combine with `zip`/`flatMap` |
| `@Transactional` on non-reactive method | Works only on `Mono`/`Flux` return types in R2DBC context |
| Missing `serverZoneId=UTC` in URL | MySQL server timezone mismatch causes datetime off-by-hours bugs |
