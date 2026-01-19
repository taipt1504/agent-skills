# Reactive Data Access Reference

## Table of Contents
- [R2DBC Configuration](#r2dbc-configuration)
- [R2DBC Repositories](#r2dbc-repositories)
- [Reactive MongoDB](#reactive-mongodb)
- [Reactive Redis (Lettuce)](#reactive-redis-lettuce)
- [Transaction Management](#transaction-management)
- [Connection Pooling](#connection-pooling)
- [Query Optimization](#query-optimization)
- [Caching Patterns](#caching-patterns)

## R2DBC Configuration

### Basic Configuration

```java
@Configuration
@EnableR2dbcRepositories
public class R2dbcConfig extends AbstractR2dbcConfiguration {

    @Value("${spring.r2dbc.url}")
    private String url;

    @Value("${spring.r2dbc.username}")
    private String username;

    @Value("${spring.r2dbc.password}")
    private String password;

    @Override
    public ConnectionFactory connectionFactory() {
        return ConnectionFactories.get(ConnectionFactoryOptions.builder()
            .option(ConnectionFactoryOptions.DRIVER, "postgresql")
            .option(ConnectionFactoryOptions.HOST, "localhost")
            .option(ConnectionFactoryOptions.PORT, 5432)
            .option(ConnectionFactoryOptions.DATABASE, "mydb")
            .option(ConnectionFactoryOptions.USER, username)
            .option(ConnectionFactoryOptions.PASSWORD, password)
            .build());
    }

    @Bean
    public R2dbcEntityTemplate r2dbcEntityTemplate(ConnectionFactory connectionFactory) {
        DefaultReactiveDataAccessStrategy strategy =
            new DefaultReactiveDataAccessStrategy(PostgresDialect.INSTANCE);
        R2dbcEntityTemplate template = new R2dbcEntityTemplate(connectionFactory, strategy);
        return template;
    }

    @Bean
    public ReactiveTransactionManager transactionManager(ConnectionFactory connectionFactory) {
        return new R2dbcTransactionManager(connectionFactory);
    }
}
```

### Advanced Pool Configuration

```java
@Configuration
public class R2dbcPoolConfig {

    @Bean
    public ConnectionFactory connectionFactory(R2dbcProperties properties) {
        ConnectionFactoryOptions baseOptions = ConnectionFactoryOptions.parse(properties.getUrl());

        ConnectionFactoryOptions options = ConnectionFactoryOptions.builder()
            .from(baseOptions)
            .option(ConnectionFactoryOptions.USER, properties.getUsername())
            .option(ConnectionFactoryOptions.PASSWORD, properties.getPassword())
            .build();

        ConnectionFactory connectionFactory = ConnectionFactories.get(options);

        // Wrap with connection pool
        ConnectionPoolConfiguration poolConfig = ConnectionPoolConfiguration.builder()
            .connectionFactory(connectionFactory)
            .name("r2dbc-pool")
            .initialSize(10)
            .maxSize(50)
            .maxIdleTime(Duration.ofMinutes(30))
            .maxLifeTime(Duration.ofHours(1))
            .maxCreateConnectionTime(Duration.ofSeconds(5))
            .maxAcquireTime(Duration.ofSeconds(30))
            .acquireRetry(3)
            .validationQuery("SELECT 1")
            .validationDepth(ValidationDepth.LOCAL)
            .registerJmx(true)
            .build();

        return new ConnectionPool(poolConfig);
    }

    @Bean
    public ConnectionPoolMetrics connectionPoolMetrics(
            ConnectionFactory connectionFactory,
            MeterRegistry meterRegistry) {
        if (connectionFactory instanceof ConnectionPool pool) {
            return new ConnectionPoolMetrics(pool, "r2dbc-pool", meterRegistry);
        }
        return null;
    }
}
```

### Application Properties

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://localhost:5432/mydb
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    pool:
      enabled: true
      initial-size: 10
      max-size: 50
      max-idle-time: 30m
      max-life-time: 1h
      validation-query: SELECT 1

  flyway:
    enabled: true
    locations: classpath:db/migration
    # Flyway uses JDBC, needs separate config
    url: jdbc:postgresql://localhost:5432/mydb
    user: ${DB_USERNAME}
    password: ${DB_PASSWORD}
```

## R2DBC Repositories

### Entity Definition

```java
@Table("users")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User {

    @Id
    private Long id;

    @Column("email")
    private String email;

    @Column("username")
    private String username;

    @Column("password_hash")
    private String passwordHash;

    @Column("status")
    private UserStatus status;

    @Column("created_at")
    private Instant createdAt;

    @Column("updated_at")
    private Instant updatedAt;

    @Version
    private Long version;

    // Transient field - not persisted
    @Transient
    private List<Role> roles;
}

public enum UserStatus {
    ACTIVE, INACTIVE, SUSPENDED, PENDING_VERIFICATION
}
```

### Repository Interface

```java
public interface UserRepository extends ReactiveCrudRepository<User, Long> {

    Mono<User> findByEmail(String email);

    Mono<User> findByUsername(String username);

    Flux<User> findByStatus(UserStatus status);

    @Query("SELECT * FROM users WHERE email = :email AND status = 'ACTIVE'")
    Mono<User> findActiveByEmail(@Param("email") String email);

    @Query("SELECT * FROM users WHERE created_at > :since ORDER BY created_at DESC")
    Flux<User> findRecentUsers(@Param("since") Instant since);

    @Query("SELECT * FROM users WHERE username LIKE :pattern")
    Flux<User> searchByUsername(@Param("pattern") String pattern);

    @Query("SELECT COUNT(*) FROM users WHERE status = :status")
    Mono<Long> countByStatus(@Param("status") UserStatus status);

    @Modifying
    @Query("UPDATE users SET status = :status, updated_at = NOW() WHERE id = :id")
    Mono<Integer> updateStatus(@Param("id") Long id, @Param("status") UserStatus status);

    @Modifying
    @Query("DELETE FROM users WHERE status = 'INACTIVE' AND updated_at < :before")
    Mono<Integer> deleteInactiveUsersBefore(@Param("before") Instant before);

    Mono<Boolean> existsByEmail(String email);

    Mono<Boolean> existsByUsername(String username);
}
```

### Custom Repository Implementation

```java
public interface CustomUserRepository {
    Flux<User> findByFilters(UserSearchCriteria criteria);
    Mono<Page<User>> findAllPaged(Pageable pageable);
    Flux<UserWithRoles> findAllWithRoles();
}

@Repository
@RequiredArgsConstructor
public class CustomUserRepositoryImpl implements CustomUserRepository {

    private final DatabaseClient databaseClient;
    private final R2dbcEntityTemplate template;

    @Override
    public Flux<User> findByFilters(UserSearchCriteria criteria) {
        StringBuilder sql = new StringBuilder("SELECT * FROM users WHERE 1=1");
        Map<String, Object> params = new HashMap<>();

        if (criteria.getStatus() != null) {
            sql.append(" AND status = :status");
            params.put("status", criteria.getStatus().name());
        }

        if (criteria.getEmail() != null) {
            sql.append(" AND email LIKE :email");
            params.put("email", "%" + criteria.getEmail() + "%");
        }

        if (criteria.getCreatedAfter() != null) {
            sql.append(" AND created_at > :createdAfter");
            params.put("createdAfter", criteria.getCreatedAfter());
        }

        if (criteria.getCreatedBefore() != null) {
            sql.append(" AND created_at < :createdBefore");
            params.put("createdBefore", criteria.getCreatedBefore());
        }

        sql.append(" ORDER BY created_at DESC");

        if (criteria.getLimit() != null) {
            sql.append(" LIMIT :limit");
            params.put("limit", criteria.getLimit());
        }

        DatabaseClient.GenericExecuteSpec spec = databaseClient.sql(sql.toString());
        for (Map.Entry<String, Object> entry : params.entrySet()) {
            spec = spec.bind(entry.getKey(), entry.getValue());
        }

        return spec.map((row, metadata) -> mapToUser(row)).all();
    }

    @Override
    public Mono<Page<User>> findAllPaged(Pageable pageable) {
        String countQuery = "SELECT COUNT(*) FROM users";
        String dataQuery = "SELECT * FROM users ORDER BY " +
            pageable.getSort().stream()
                .map(order -> order.getProperty() + " " + order.getDirection())
                .collect(Collectors.joining(", ")) +
            " LIMIT :limit OFFSET :offset";

        Mono<Long> countMono = databaseClient.sql(countQuery)
            .map((row, metadata) -> row.get(0, Long.class))
            .one();

        Flux<User> dataFlux = databaseClient.sql(dataQuery)
            .bind("limit", pageable.getPageSize())
            .bind("offset", pageable.getOffset())
            .map((row, metadata) -> mapToUser(row))
            .all();

        return Mono.zip(dataFlux.collectList(), countMono)
            .map(tuple -> new PageImpl<>(tuple.getT1(), pageable, tuple.getT2()));
    }

    @Override
    public Flux<UserWithRoles> findAllWithRoles() {
        String sql = """
            SELECT u.*, r.id as role_id, r.name as role_name
            FROM users u
            LEFT JOIN user_roles ur ON u.id = ur.user_id
            LEFT JOIN roles r ON ur.role_id = r.id
            ORDER BY u.id
            """;

        return databaseClient.sql(sql)
            .map((row, metadata) -> new UserRoleRow(
                row.get("id", Long.class),
                row.get("email", String.class),
                row.get("username", String.class),
                row.get("status", String.class),
                row.get("role_id", Long.class),
                row.get("role_name", String.class)
            ))
            .all()
            .bufferUntilChanged(UserRoleRow::userId)
            .map(this::aggregateUserWithRoles);
    }

    private User mapToUser(Row row) {
        return User.builder()
            .id(row.get("id", Long.class))
            .email(row.get("email", String.class))
            .username(row.get("username", String.class))
            .passwordHash(row.get("password_hash", String.class))
            .status(UserStatus.valueOf(row.get("status", String.class)))
            .createdAt(row.get("created_at", Instant.class))
            .updatedAt(row.get("updated_at", Instant.class))
            .version(row.get("version", Long.class))
            .build();
    }

    private UserWithRoles aggregateUserWithRoles(List<UserRoleRow> rows) {
        UserRoleRow first = rows.get(0);
        List<Role> roles = rows.stream()
            .filter(r -> r.roleId() != null)
            .map(r -> new Role(r.roleId(), r.roleName()))
            .distinct()
            .collect(Collectors.toList());

        return new UserWithRoles(
            first.userId(),
            first.email(),
            first.username(),
            UserStatus.valueOf(first.status()),
            roles
        );
    }
}
```

### R2dbcEntityTemplate Usage

```java
@Service
@RequiredArgsConstructor
public class UserEntityService {

    private final R2dbcEntityTemplate template;

    public Mono<User> findById(Long id) {
        return template.selectOne(
            Query.query(Criteria.where("id").is(id)),
            User.class
        );
    }

    public Flux<User> findByStatusWithPaging(UserStatus status, int page, int size) {
        return template.select(User.class)
            .matching(Query.query(Criteria.where("status").is(status))
                .sort(Sort.by(Sort.Direction.DESC, "createdAt"))
                .limit(size)
                .offset((long) page * size))
            .all();
    }

    public Mono<User> save(User user) {
        if (user.getId() == null) {
            user.setCreatedAt(Instant.now());
            return template.insert(user);
        }
        user.setUpdatedAt(Instant.now());
        return template.update(user);
    }

    public Mono<Long> deleteByStatus(UserStatus status) {
        return template.delete(User.class)
            .matching(Query.query(Criteria.where("status").is(status)))
            .all();
    }

    public Mono<Boolean> exists(Long id) {
        return template.exists(
            Query.query(Criteria.where("id").is(id)),
            User.class
        );
    }

    public Mono<Long> count() {
        return template.count(Query.empty(), User.class);
    }

    public Mono<Long> countByStatus(UserStatus status) {
        return template.count(
            Query.query(Criteria.where("status").is(status)),
            User.class
        );
    }
}
```

## Reactive MongoDB

### Configuration

```java
@Configuration
@EnableReactiveMongoRepositories
public class MongoConfig extends AbstractReactiveMongoConfiguration {

    @Value("${spring.data.mongodb.uri}")
    private String mongoUri;

    @Value("${spring.data.mongodb.database}")
    private String database;

    @Override
    protected String getDatabaseName() {
        return database;
    }

    @Override
    public MongoClient reactiveMongoClient() {
        MongoClientSettings settings = MongoClientSettings.builder()
            .applyConnectionString(new ConnectionString(mongoUri))
            .applyToConnectionPoolSettings(builder -> builder
                .maxSize(100)
                .minSize(10)
                .maxWaitTime(5, TimeUnit.SECONDS)
                .maxConnectionIdleTime(30, TimeUnit.MINUTES))
            .applyToSocketSettings(builder -> builder
                .connectTimeout(5, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS))
            .retryWrites(true)
            .retryReads(true)
            .build();

        return MongoClients.create(settings);
    }

    @Bean
    public ReactiveMongoTemplate reactiveMongoTemplate() {
        return new ReactiveMongoTemplate(reactiveMongoClient(), getDatabaseName());
    }

    @Override
    protected Collection<String> getMappingBasePackages() {
        return Collections.singletonList("com.example.domain");
    }
}
```

### Document Entities

```java
@Document(collection = "products")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Product {

    @Id
    private String id;

    @Field("name")
    @Indexed
    private String name;

    @Field("description")
    private String description;

    @Field("price")
    private BigDecimal price;

    @Field("category")
    @Indexed
    private String category;

    @Field("tags")
    private List<String> tags;

    @Field("attributes")
    private Map<String, Object> attributes;

    @Field("inventory")
    private Inventory inventory;

    @Field("created_at")
    private Instant createdAt;

    @Field("updated_at")
    private Instant updatedAt;

    @Version
    private Long version;

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Inventory {
        private int quantity;
        private int reserved;
        private String warehouse;
    }
}

@Document(collection = "orders")
@CompoundIndex(def = "{'userId': 1, 'status': 1}")
@Data
@Builder
public class Order {

    @Id
    private String id;

    @Field("user_id")
    @Indexed
    private String userId;

    @Field("items")
    private List<OrderItem> items;

    @Field("status")
    @Indexed
    private OrderStatus status;

    @Field("total")
    private BigDecimal total;

    @Field("shipping_address")
    private Address shippingAddress;

    @Field("created_at")
    @Indexed
    private Instant createdAt;

    @Data
    @AllArgsConstructor
    public static class OrderItem {
        private String productId;
        private String productName;
        private int quantity;
        private BigDecimal price;
    }
}
```

### MongoDB Repository

```java
public interface ProductRepository extends ReactiveMongoRepository<Product, String> {

    Flux<Product> findByCategory(String category);

    Flux<Product> findByCategoryAndPriceLessThan(String category, BigDecimal maxPrice);

    @Query("{ 'tags': { $in: ?0 } }")
    Flux<Product> findByTagsIn(List<String> tags);

    @Query("{ 'name': { $regex: ?0, $options: 'i' } }")
    Flux<Product> searchByName(String namePattern);

    @Query("{ 'price': { $gte: ?0, $lte: ?1 } }")
    Flux<Product> findByPriceRange(BigDecimal minPrice, BigDecimal maxPrice);

    @Query("{ 'inventory.quantity': { $gt: 0 } }")
    Flux<Product> findInStock();

    @Aggregation(pipeline = {
        "{ $match: { category: ?0 } }",
        "{ $group: { _id: null, avgPrice: { $avg: '$price' }, count: { $sum: 1 } } }"
    })
    Mono<CategoryStats> getCategoryStats(String category);

    @Aggregation(pipeline = {
        "{ $unwind: '$tags' }",
        "{ $group: { _id: '$tags', count: { $sum: 1 } } }",
        "{ $sort: { count: -1 } }",
        "{ $limit: 10 }"
    })
    Flux<TagCount> getTopTags();

    Mono<Long> countByCategory(String category);

    Mono<Boolean> existsByName(String name);
}

public interface OrderRepository extends ReactiveMongoRepository<Order, String> {

    Flux<Order> findByUserId(String userId);

    Flux<Order> findByUserIdAndStatus(String userId, OrderStatus status);

    @Query("{ 'userId': ?0, 'createdAt': { $gte: ?1 } }")
    Flux<Order> findRecentOrdersByUser(String userId, Instant since);

    @Aggregation(pipeline = {
        "{ $match: { userId: ?0 } }",
        "{ $group: { _id: null, total: { $sum: '$total' }, count: { $sum: 1 } } }"
    })
    Mono<UserOrderStats> getUserOrderStats(String userId);
}
```

### ReactiveMongoTemplate Usage

```java
@Service
@RequiredArgsConstructor
public class ProductMongoService {

    private final ReactiveMongoTemplate mongoTemplate;

    public Flux<Product> searchProducts(ProductSearchCriteria criteria) {
        Query query = new Query();

        if (criteria.getCategory() != null) {
            query.addCriteria(Criteria.where("category").is(criteria.getCategory()));
        }

        if (criteria.getMinPrice() != null) {
            query.addCriteria(Criteria.where("price").gte(criteria.getMinPrice()));
        }

        if (criteria.getMaxPrice() != null) {
            query.addCriteria(Criteria.where("price").lte(criteria.getMaxPrice()));
        }

        if (criteria.getTags() != null && !criteria.getTags().isEmpty()) {
            query.addCriteria(Criteria.where("tags").in(criteria.getTags()));
        }

        if (criteria.getNamePattern() != null) {
            query.addCriteria(Criteria.where("name")
                .regex(criteria.getNamePattern(), "i"));
        }

        if (criteria.isInStockOnly()) {
            query.addCriteria(Criteria.where("inventory.quantity").gt(0));
        }

        // Pagination
        query.with(PageRequest.of(
            criteria.getPage(),
            criteria.getSize(),
            Sort.by(Sort.Direction.DESC, "createdAt")
        ));

        return mongoTemplate.find(query, Product.class);
    }

    public Mono<Product> updateInventory(String productId, int quantityChange) {
        Query query = Query.query(Criteria.where("id").is(productId));
        Update update = new Update()
            .inc("inventory.quantity", quantityChange)
            .set("updatedAt", Instant.now());

        return mongoTemplate.findAndModify(
            query,
            update,
            FindAndModifyOptions.options().returnNew(true),
            Product.class
        );
    }

    public Mono<UpdateResult> bulkUpdatePrices(String category, BigDecimal percentage) {
        Query query = Query.query(Criteria.where("category").is(category));
        Update update = new Update()
            .mul("price", 1 + percentage.doubleValue() / 100)
            .set("updatedAt", Instant.now());

        return mongoTemplate.updateMulti(query, update, Product.class);
    }

    public Flux<CategorySummary> aggregateByCategoryWithStats() {
        Aggregation aggregation = Aggregation.newAggregation(
            Aggregation.group("category")
                .count().as("productCount")
                .avg("price").as("avgPrice")
                .min("price").as("minPrice")
                .max("price").as("maxPrice")
                .sum("inventory.quantity").as("totalInventory"),
            Aggregation.project()
                .andExpression("_id").as("category")
                .andInclude("productCount", "avgPrice", "minPrice", "maxPrice", "totalInventory"),
            Aggregation.sort(Sort.Direction.DESC, "productCount")
        );

        return mongoTemplate.aggregate(aggregation, "products", CategorySummary.class);
    }

    public Flux<Product> findNearbyProducts(double longitude, double latitude, double maxDistanceKm) {
        NearQuery nearQuery = NearQuery.near(longitude, latitude)
            .maxDistance(new Distance(maxDistanceKm, Metrics.KILOMETERS))
            .spherical(true);

        return mongoTemplate.geoNear(nearQuery, Product.class)
            .map(GeoResult::getContent);
    }
}
```

### Change Streams

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class ProductChangeStreamService {

    private final ReactiveMongoTemplate mongoTemplate;
    private final ProductEventPublisher eventPublisher;

    @PostConstruct
    public void startChangeStream() {
        watchProducts()
            .subscribe(
                event -> log.info("Product change: {}", event),
                error -> log.error("Change stream error", error)
            );
    }

    public Flux<ProductChangeEvent> watchProducts() {
        ChangeStreamOptions options = ChangeStreamOptions.builder()
            .filter(Aggregation.newAggregation(
                Aggregation.match(Criteria.where("operationType")
                    .in("insert", "update", "replace", "delete"))
            ))
            .returnFullDocumentOnUpdate()
            .build();

        return mongoTemplate.changeStream(
                "products",
                options,
                Product.class
            )
            .map(event -> new ProductChangeEvent(
                event.getOperationType().getValue(),
                event.getBody(),
                event.getTimestamp()
            ))
            .doOnNext(eventPublisher::publish);
    }

    public Flux<OrderChangeEvent> watchOrdersForUser(String userId) {
        ChangeStreamOptions options = ChangeStreamOptions.builder()
            .filter(Aggregation.newAggregation(
                Aggregation.match(Criteria.where("fullDocument.userId").is(userId))
            ))
            .returnFullDocumentOnUpdate()
            .build();

        return mongoTemplate.changeStream("orders", options, Order.class)
            .map(event -> new OrderChangeEvent(
                event.getOperationType().getValue(),
                event.getBody()
            ));
    }
}
```

## Reactive Redis (Lettuce)

### Configuration

```java
@Configuration
public class RedisConfig {

    @Bean
    public ReactiveRedisConnectionFactory reactiveRedisConnectionFactory() {
        LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
            .commandTimeout(Duration.ofSeconds(2))
            .shutdownTimeout(Duration.ofMillis(100))
            .clientOptions(ClientOptions.builder()
                .autoReconnect(true)
                .disconnectedBehavior(ClientOptions.DisconnectedBehavior.REJECT_COMMANDS)
                .build())
            .clientResources(DefaultClientResources.builder()
                .ioThreadPoolSize(4)
                .computationThreadPoolSize(4)
                .build())
            .build();

        RedisStandaloneConfiguration serverConfig = new RedisStandaloneConfiguration();
        serverConfig.setHostName("localhost");
        serverConfig.setPort(6379);
        serverConfig.setPassword(RedisPassword.of("password"));
        serverConfig.setDatabase(0);

        return new LettuceConnectionFactory(serverConfig, clientConfig);
    }
}
```
