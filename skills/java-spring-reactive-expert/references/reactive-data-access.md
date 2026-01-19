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

    @Bean
    public ReactiveRedisTemplate<String, Object> reactiveRedisTemplate(
            ReactiveRedisConnectionFactory factory) {

        StringRedisSerializer keySerializer = new StringRedisSerializer();
        Jackson2JsonRedisSerializer<Object> valueSerializer =
            new Jackson2JsonRedisSerializer<>(Object.class);

        RedisSerializationContext<String, Object> context =
            RedisSerializationContext.<String, Object>newSerializationContext()
                .key(keySerializer)
                .value(valueSerializer)
                .hashKey(keySerializer)
                .hashValue(valueSerializer)
                .build();

        return new ReactiveRedisTemplate<>(factory, context);
    }

    @Bean
    public ReactiveStringRedisTemplate reactiveStringRedisTemplate(
            ReactiveRedisConnectionFactory factory) {
        return new ReactiveStringRedisTemplate(factory);
    }
}
```

### Cluster Configuration

```java
@Configuration
public class RedisClusterConfig {

    @Bean
    public ReactiveRedisConnectionFactory reactiveRedisClusterConnectionFactory() {
        RedisClusterConfiguration clusterConfig = new RedisClusterConfiguration(
            List.of(
                "redis-node-1:6379",
                "redis-node-2:6379",
                "redis-node-3:6379"
            )
        );
        clusterConfig.setPassword(RedisPassword.of("password"));
        clusterConfig.setMaxRedirects(3);

        LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
            .commandTimeout(Duration.ofSeconds(2))
            .readFrom(ReadFrom.REPLICA_PREFERRED)
            .clientOptions(ClusterClientOptions.builder()
                .autoReconnect(true)
                .validateClusterNodeMembership(false)
                .topologyRefreshOptions(ClusterTopologyRefreshOptions.builder()
                    .enablePeriodicRefresh(Duration.ofMinutes(1))
                    .enableAllAdaptiveRefreshTriggers()
                    .build())
                .build())
            .build();

        return new LettuceConnectionFactory(clusterConfig, clientConfig);
    }
}
```

### Redis Operations Service

```java
@Service
@RequiredArgsConstructor
public class RedisService {

    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private final ReactiveStringRedisTemplate stringRedisTemplate;

    // String operations
    public Mono<Boolean> set(String key, Object value, Duration ttl) {
        return redisTemplate.opsForValue().set(key, value, ttl);
    }

    public <T> Mono<T> get(String key, Class<T> type) {
        return redisTemplate.opsForValue().get(key)
            .map(value -> objectMapper.convertValue(value, type));
    }

    public Mono<Boolean> delete(String key) {
        return redisTemplate.delete(key).map(count -> count > 0);
    }

    public Mono<Long> increment(String key) {
        return stringRedisTemplate.opsForValue().increment(key);
    }

    public Mono<Long> incrementBy(String key, long delta) {
        return stringRedisTemplate.opsForValue().increment(key, delta);
    }

    // Hash operations
    public Mono<Boolean> hSet(String key, String field, Object value) {
        return redisTemplate.opsForHash().put(key, field, value);
    }

    public <T> Mono<T> hGet(String key, String field, Class<T> type) {
        return redisTemplate.<String, Object>opsForHash().get(key, field)
            .map(value -> objectMapper.convertValue(value, type));
    }

    public Flux<Map.Entry<String, Object>> hGetAll(String key) {
        return redisTemplate.<String, Object>opsForHash().entries(key);
    }

    public Mono<Long> hDelete(String key, String... fields) {
        return redisTemplate.opsForHash().remove(key, (Object[]) fields);
    }

    // List operations
    public Mono<Long> lPush(String key, Object... values) {
        return redisTemplate.opsForList().leftPushAll(key, values);
    }

    public Mono<Long> rPush(String key, Object... values) {
        return redisTemplate.opsForList().rightPushAll(key, values);
    }

    public <T> Mono<T> lPop(String key, Class<T> type) {
        return redisTemplate.opsForList().leftPop(key)
            .map(value -> objectMapper.convertValue(value, type));
    }

    public Flux<Object> lRange(String key, long start, long end) {
        return redisTemplate.opsForList().range(key, start, end);
    }

    // Set operations
    public Mono<Long> sAdd(String key, Object... values) {
        return redisTemplate.opsForSet().add(key, values);
    }

    public Mono<Boolean> sIsMember(String key, Object value) {
        return redisTemplate.opsForSet().isMember(key, value);
    }

    public Flux<Object> sMembers(String key) {
        return redisTemplate.opsForSet().members(key);
    }

    // Sorted set operations
    public Mono<Boolean> zAdd(String key, Object value, double score) {
        return redisTemplate.opsForZSet().add(key, value, score);
    }

    public Flux<Object> zRange(String key, long start, long end) {
        return redisTemplate.opsForZSet().range(key, Range.closed(start, end));
    }

    public Flux<ZSetOperations.TypedTuple<Object>> zRangeWithScores(String key, long start, long end) {
        return redisTemplate.opsForZSet().rangeWithScores(key, Range.closed(start, end));
    }

    // TTL operations
    public Mono<Boolean> expire(String key, Duration duration) {
        return redisTemplate.expire(key, duration);
    }

    public Mono<Duration> getTtl(String key) {
        return redisTemplate.getExpire(key);
    }

    // Pattern operations
    public Flux<String> keys(String pattern) {
        return redisTemplate.keys(pattern);
    }

    public Mono<Long> deleteByPattern(String pattern) {
        return redisTemplate.keys(pattern)
            .flatMap(redisTemplate::delete)
            .reduce(0L, Long::sum);
    }
}
```

### Redis Pub/Sub

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RedisPubSubService {

    private final ReactiveStringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;

    public Mono<Long> publish(String channel, Object message) {
        return Mono.fromCallable(() -> objectMapper.writeValueAsString(message))
            .flatMap(json -> redisTemplate.convertAndSend(channel, json));
    }

    public <T> Flux<T> subscribe(String channel, Class<T> messageType) {
        return redisTemplate.listenToChannel(channel)
            .map(ReactiveSubscription.Message::getMessage)
            .flatMap(json -> {
                try {
                    return Mono.just(objectMapper.readValue(json, messageType));
                } catch (JsonProcessingException e) {
                    log.error("Failed to deserialize message", e);
                    return Mono.empty();
                }
            });
    }

    public <T> Flux<T> subscribePattern(String pattern, Class<T> messageType) {
        return redisTemplate.listenToPattern(pattern)
            .map(ReactiveSubscription.PatternMessage::getMessage)
            .flatMap(json -> {
                try {
                    return Mono.just(objectMapper.readValue(json, messageType));
                } catch (JsonProcessingException e) {
                    log.error("Failed to deserialize message", e);
                    return Mono.empty();
                }
            });
    }
}
```

### Distributed Lock with Redis

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RedisDistributedLock {

    private final ReactiveStringRedisTemplate redisTemplate;

    private static final String LOCK_PREFIX = "lock:";
    private static final Duration DEFAULT_LOCK_TIMEOUT = Duration.ofSeconds(30);

    public Mono<Boolean> tryLock(String lockKey, String lockValue, Duration timeout) {
        String key = LOCK_PREFIX + lockKey;
        return redisTemplate.opsForValue()
            .setIfAbsent(key, lockValue, timeout)
            .defaultIfEmpty(false);
    }

    public Mono<Boolean> unlock(String lockKey, String lockValue) {
        String key = LOCK_PREFIX + lockKey;
        String script = """
            if redis.call('get', KEYS[1]) == ARGV[1] then
                return redis.call('del', KEYS[1])
            else
                return 0
            end
            """;

        return redisTemplate.execute(
                RedisScript.of(script, Long.class),
                List.of(key),
                List.of(lockValue)
            )
            .next()
            .map(result -> result == 1L)
            .defaultIfEmpty(false);
    }

    public <T> Mono<T> executeWithLock(String lockKey, Duration lockTimeout, Mono<T> operation) {
        String lockValue = UUID.randomUUID().toString();

        return tryLock(lockKey, lockValue, lockTimeout)
            .flatMap(acquired -> {
                if (!acquired) {
                    return Mono.error(new LockAcquisitionException("Failed to acquire lock: " + lockKey));
                }

                return operation
                    .doFinally(signal -> unlock(lockKey, lockValue)
                        .subscribe(
                            released -> {
                                if (!released) {
                                    log.warn("Failed to release lock: {}", lockKey);
                                }
                            },
                            error -> log.error("Error releasing lock: {}", lockKey, error)
                        ));
            });
    }

    public Mono<Boolean> extendLock(String lockKey, String lockValue, Duration extension) {
        String key = LOCK_PREFIX + lockKey;
        String script = """
            if redis.call('get', KEYS[1]) == ARGV[1] then
                return redis.call('pexpire', KEYS[1], ARGV[2])
            else
                return 0
            end
            """;

        return redisTemplate.execute(
                RedisScript.of(script, Long.class),
                List.of(key),
                List.of(lockValue, String.valueOf(extension.toMillis()))
            )
            .next()
            .map(result -> result == 1L)
            .defaultIfEmpty(false);
    }
}
```

## Transaction Management

### R2DBC Transactions

```java
@Service
@RequiredArgsConstructor
public class TransactionalUserService {

    private final UserRepository userRepository;
    private final AuditRepository auditRepository;
    private final TransactionalOperator transactionalOperator;

    // Using @Transactional annotation
    @Transactional
    public Mono<User> createUserWithAudit(CreateUserRequest request) {
        User user = User.builder()
            .email(request.getEmail())
            .username(request.getUsername())
            .status(UserStatus.PENDING_VERIFICATION)
            .createdAt(Instant.now())
            .build();

        return userRepository.save(user)
            .flatMap(savedUser -> {
                AuditLog audit = AuditLog.builder()
                    .action("USER_CREATED")
                    .entityId(savedUser.getId().toString())
                    .timestamp(Instant.now())
                    .build();
                return auditRepository.save(audit)
                    .thenReturn(savedUser);
            });
    }

    // Using TransactionalOperator programmatically
    public Mono<User> createUserWithOperator(CreateUserRequest request) {
        return transactionalOperator.transactional(
            Mono.defer(() -> {
                User user = User.builder()
                    .email(request.getEmail())
                    .username(request.getUsername())
                    .status(UserStatus.PENDING_VERIFICATION)
                    .createdAt(Instant.now())
                    .build();

                return userRepository.save(user)
                    .flatMap(savedUser -> {
                        AuditLog audit = AuditLog.builder()
                            .action("USER_CREATED")
                            .entityId(savedUser.getId().toString())
                            .timestamp(Instant.now())
                            .build();
                        return auditRepository.save(audit)
                            .thenReturn(savedUser);
                    });
            })
        );
    }

    // Transaction with rollback conditions
    @Transactional(rollbackFor = {ValidationException.class, DuplicateException.class})
    public Mono<User> createUserWithRollback(CreateUserRequest request) {
        return checkDuplicate(request.getEmail())
            .then(validateRequest(request))
            .then(Mono.defer(() -> {
                User user = mapToUser(request);
                return userRepository.save(user);
            }));
    }

    // Read-only transaction
    @Transactional(readOnly = true)
    public Flux<User> findAllUsers() {
        return userRepository.findAll();
    }

    // Custom isolation level
    @Transactional(isolation = Isolation.SERIALIZABLE)
    public Mono<Void> transferCredits(Long fromUserId, Long toUserId, int amount) {
        return userRepository.findById(fromUserId)
            .flatMap(fromUser -> {
                if (fromUser.getCredits() < amount) {
                    return Mono.error(new InsufficientCreditsException());
                }
                fromUser.setCredits(fromUser.getCredits() - amount);
                return userRepository.save(fromUser);
            })
            .then(userRepository.findById(toUserId))
            .flatMap(toUser -> {
                toUser.setCredits(toUser.getCredits() + amount);
                return userRepository.save(toUser);
            })
            .then();
    }
}
```

### MongoDB Transactions

```java
@Service
@RequiredArgsConstructor
public class MongoTransactionalService {

    private final ReactiveMongoTemplate mongoTemplate;
    private final ReactiveMongoTransactionManager transactionManager;

    @Transactional
    public Mono<Order> createOrderWithInventoryUpdate(CreateOrderRequest request) {
        return Flux.fromIterable(request.getItems())
            .flatMap(item -> updateInventory(item.getProductId(), -item.getQuantity()))
            .then(Mono.defer(() -> {
                Order order = buildOrder(request);
                return mongoTemplate.insert(order);
            }));
    }

    private Mono<UpdateResult> updateInventory(String productId, int quantityChange) {
        Query query = Query.query(Criteria.where("_id").is(productId)
            .and("inventory.quantity").gte(-quantityChange));

        Update update = new Update()
            .inc("inventory.quantity", quantityChange)
            .set("updatedAt", Instant.now());

        return mongoTemplate.updateFirst(query, update, Product.class)
            .flatMap(result -> {
                if (result.getModifiedCount() == 0) {
                    return Mono.error(new InsufficientInventoryException(productId));
                }
                return Mono.just(result);
            });
    }

    // Programmatic transaction control
    public Mono<Order> createOrderProgrammatic(CreateOrderRequest request) {
        TransactionalOperator operator = TransactionalOperator.create(transactionManager);

        return operator.transactional(
            Flux.fromIterable(request.getItems())
                .flatMap(item -> updateInventory(item.getProductId(), -item.getQuantity()))
                .then(Mono.defer(() -> {
                    Order order = buildOrder(request);
                    return mongoTemplate.insert(order);
                }))
        );
    }
}
```

## Connection Pooling

### R2DBC Connection Pool Metrics

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class ConnectionPoolMetricsCollector {

    private final ConnectionFactory connectionFactory;
    private final MeterRegistry meterRegistry;

    @PostConstruct
    public void registerMetrics() {
        if (connectionFactory instanceof ConnectionPool pool) {
            PoolMetrics poolMetrics = pool.getMetrics().orElse(null);

            if (poolMetrics != null) {
                Gauge.builder("r2dbc.pool.acquired", poolMetrics, PoolMetrics::acquiredSize)
                    .description("Current acquired connections")
                    .register(meterRegistry);

                Gauge.builder("r2dbc.pool.allocated", poolMetrics, PoolMetrics::allocatedSize)
                    .description("Current allocated connections")
                    .register(meterRegistry);

                Gauge.builder("r2dbc.pool.idle", poolMetrics, PoolMetrics::idleSize)
                    .description("Current idle connections")
                    .register(meterRegistry);

                Gauge.builder("r2dbc.pool.pending", poolMetrics, PoolMetrics::pendingAcquireSize)
                    .description("Pending connection acquisitions")
                    .register(meterRegistry);

                Gauge.builder("r2dbc.pool.max", poolMetrics, PoolMetrics::getMaxAllocatedSize)
                    .description("Maximum pool size")
                    .register(meterRegistry);
            }
        }
    }
}
```

### Connection Pool Health Indicator

```java
@Component
@RequiredArgsConstructor
public class R2dbcPoolHealthIndicator implements ReactiveHealthIndicator {

    private final ConnectionFactory connectionFactory;

    @Override
    public Mono<Health> health() {
        return Mono.usingWhen(
                connectionFactory.create(),
                connection -> Mono.from(connection.createStatement("SELECT 1").execute())
                    .flatMap(result -> Mono.from(result.getRowsUpdated()))
                    .map(count -> buildHealthUp()),
                Connection::close
            )
            .timeout(Duration.ofSeconds(5))
            .onErrorResume(e -> Mono.just(buildHealthDown(e)));
    }

    private Health buildHealthUp() {
        Health.Builder builder = Health.up();

        if (connectionFactory instanceof ConnectionPool pool) {
            pool.getMetrics().ifPresent(metrics -> {
                builder.withDetail("acquired", metrics.acquiredSize())
                    .withDetail("allocated", metrics.allocatedSize())
                    .withDetail("idle", metrics.idleSize())
                    .withDetail("pending", metrics.pendingAcquireSize())
                    .withDetail("maxSize", metrics.getMaxAllocatedSize());
            });
        }

        return builder.build();
    }

    private Health buildHealthDown(Throwable e) {
        return Health.down()
            .withDetail("error", e.getMessage())
            .build();
    }
}
```

## Query Optimization

### Batch Operations

```java
@Service
@RequiredArgsConstructor
public class BatchOperationsService {

    private final DatabaseClient databaseClient;
    private final R2dbcEntityTemplate template;

    public Mono<Long> batchInsert(List<User> users) {
        if (users.isEmpty()) {
            return Mono.just(0L);
        }

        StringBuilder sql = new StringBuilder("INSERT INTO users (email, username, status, created_at) VALUES ");
        List<Object> params = new ArrayList<>();

        for (int i = 0; i < users.size(); i++) {
            if (i > 0) sql.append(", ");
            sql.append("($").append(i * 4 + 1)
                .append(", $").append(i * 4 + 2)
                .append(", $").append(i * 4 + 3)
                .append(", $").append(i * 4 + 4).append(")");

            User user = users.get(i);
            params.add(user.getEmail());
            params.add(user.getUsername());
            params.add(user.getStatus().name());
            params.add(user.getCreatedAt());
        }

        DatabaseClient.GenericExecuteSpec spec = databaseClient.sql(sql.toString());
        for (int i = 0; i < params.size(); i++) {
            spec = spec.bind(i, params.get(i));
        }

        return spec.fetch().rowsUpdated();
    }

    public Flux<User> batchInsertReturning(List<User> users) {
        return Flux.fromIterable(users)
            .buffer(100) // Batch size
            .flatMap(batch -> Flux.fromIterable(batch)
                .flatMap(template::insert))
            .subscribeOn(Schedulers.boundedElastic());
    }

    public Mono<Long> batchUpdate(List<Long> ids, UserStatus newStatus) {
        if (ids.isEmpty()) {
            return Mono.just(0L);
        }

        String placeholders = ids.stream()
            .map(id -> "?")
            .collect(Collectors.joining(", "));

        String sql = "UPDATE users SET status = ?, updated_at = NOW() WHERE id IN (" + placeholders + ")";

        DatabaseClient.GenericExecuteSpec spec = databaseClient.sql(sql)
            .bind(0, newStatus.name());

        for (int i = 0; i < ids.size(); i++) {
            spec = spec.bind(i + 1, ids.get(i));
        }

        return spec.fetch().rowsUpdated();
    }

    public Mono<Long> batchDelete(List<Long> ids) {
        if (ids.isEmpty()) {
            return Mono.just(0L);
        }

        return template.delete(User.class)
            .matching(Query.query(Criteria.where("id").in(ids)))
            .all();
    }
}
```

### Cursor-Based Pagination

```java
@Service
@RequiredArgsConstructor
public class CursorPaginationService {

    private final DatabaseClient databaseClient;

    public Flux<User> findUsersWithCursor(String cursor, int limit) {
        String sql;
        DatabaseClient.GenericExecuteSpec spec;

        if (cursor == null) {
            sql = "SELECT * FROM users ORDER BY created_at DESC, id DESC LIMIT :limit";
            spec = databaseClient.sql(sql).bind("limit", limit);
        } else {
            // Decode cursor: "createdAt:id"
            String[] parts = cursor.split(":");
            Instant createdAt = Instant.parse(parts[0]);
            Long id = Long.parseLong(parts[1]);

            sql = """
                SELECT * FROM users
                WHERE (created_at, id) < (:createdAt, :id)
                ORDER BY created_at DESC, id DESC
                LIMIT :limit
                """;
            spec = databaseClient.sql(sql)
                .bind("createdAt", createdAt)
                .bind("id", id)
                .bind("limit", limit);
        }

        return spec.map((row, metadata) -> mapToUser(row)).all();
    }

    public Mono<CursorPage<User>> findUsersPage(String cursor, int limit) {
        return findUsersWithCursor(cursor, limit + 1) // Fetch one extra to check hasNext
            .collectList()
            .map(users -> {
                boolean hasNext = users.size() > limit;
                List<User> pageUsers = hasNext ? users.subList(0, limit) : users;

                String nextCursor = null;
                if (hasNext && !pageUsers.isEmpty()) {
                    User last = pageUsers.get(pageUsers.size() - 1);
                    nextCursor = last.getCreatedAt() + ":" + last.getId();
                }

                return new CursorPage<>(pageUsers, nextCursor, hasNext);
            });
    }

    @Data
    @AllArgsConstructor
    public static class CursorPage<T> {
        private List<T> items;
        private String nextCursor;
        private boolean hasNext;
    }
}
```

## Caching Patterns

### Cache-Aside Pattern

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class CachingUserService {

    private final UserRepository userRepository;
    private final ReactiveRedisTemplate<String, User> redisTemplate;

    private static final String CACHE_PREFIX = "user:";
    private static final Duration CACHE_TTL = Duration.ofMinutes(30);

    public Mono<User> findById(Long id) {
        String cacheKey = CACHE_PREFIX + id;

        return redisTemplate.opsForValue().get(cacheKey)
            .doOnNext(user -> log.debug("Cache hit for user: {}", id))
            .switchIfEmpty(
                userRepository.findById(id)
                    .doOnNext(user -> log.debug("Cache miss for user: {}", id))
                    .flatMap(user -> redisTemplate.opsForValue()
                        .set(cacheKey, user, CACHE_TTL)
                        .thenReturn(user))
            );
    }

    public Mono<User> save(User user) {
        return userRepository.save(user)
            .flatMap(savedUser -> {
                String cacheKey = CACHE_PREFIX + savedUser.getId();
                return redisTemplate.opsForValue()
                    .set(cacheKey, savedUser, CACHE_TTL)
                    .thenReturn(savedUser);
            });
    }

    public Mono<Void> delete(Long id) {
        String cacheKey = CACHE_PREFIX + id;
        return userRepository.deleteById(id)
            .then(redisTemplate.delete(cacheKey))
            .then();
    }

    public Mono<Void> evictCache(Long id) {
        return redisTemplate.delete(CACHE_PREFIX + id).then();
    }

    public Mono<Void> evictAllUserCaches() {
        return redisTemplate.keys(CACHE_PREFIX + "*")
            .flatMap(redisTemplate::delete)
            .then();
    }
}
```

### Write-Through Cache

```java
@Service
@RequiredArgsConstructor
public class WriteThroughCacheService {

    private final ProductRepository productRepository;
    private final ReactiveRedisTemplate<String, Product> redisTemplate;

    private static final String CACHE_PREFIX = "product:";
    private static final Duration CACHE_TTL = Duration.ofHours(1);

    public Mono<Product> save(Product product) {
        // Write to both DB and cache atomically (best effort)
        return productRepository.save(product)
            .flatMap(saved -> {
                String cacheKey = CACHE_PREFIX + saved.getId();
                return redisTemplate.opsForValue()
                    .set(cacheKey, saved, CACHE_TTL)
                    .thenReturn(saved)
                    .onErrorResume(e -> {
                        log.warn("Failed to update cache for product: {}", saved.getId(), e);
                        return Mono.just(saved);
                    });
            });
    }

    public Mono<Product> findById(String id) {
        String cacheKey = CACHE_PREFIX + id;

        return redisTemplate.opsForValue().get(cacheKey)
            .switchIfEmpty(
                productRepository.findById(id)
                    .flatMap(product -> redisTemplate.opsForValue()
                        .set(cacheKey, product, CACHE_TTL)
                        .thenReturn(product))
            );
    }
}
```

### Cache with Refresh-Ahead

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RefreshAheadCacheService {

    private final DataRepository dataRepository;
    private final ReactiveRedisTemplate<String, CachedData> redisTemplate;

    private static final String CACHE_PREFIX = "data:";
    private static final Duration CACHE_TTL = Duration.ofMinutes(10);
    private static final Duration REFRESH_THRESHOLD = Duration.ofMinutes(2);

    public Mono<Data> getData(String id) {
        String cacheKey = CACHE_PREFIX + id;

        return redisTemplate.opsForValue().get(cacheKey)
            .flatMap(cached -> {
                if (shouldRefresh(cached)) {
                    // Trigger async refresh
                    refreshDataAsync(id, cacheKey);
                }
                return Mono.just(cached.getData());
            })
            .switchIfEmpty(loadAndCache(id, cacheKey));
    }

    private boolean shouldRefresh(CachedData cached) {
        Instant refreshTime = cached.getCachedAt().plus(CACHE_TTL.minus(REFRESH_THRESHOLD));
        return Instant.now().isAfter(refreshTime);
    }

    private void refreshDataAsync(String id, String cacheKey) {
        dataRepository.findById(id)
            .flatMap(data -> {
                CachedData cached = new CachedData(data, Instant.now());
                return redisTemplate.opsForValue().set(cacheKey, cached, CACHE_TTL);
            })
            .subscribe(
                success -> log.debug("Refreshed cache for: {}", id),
                error -> log.warn("Failed to refresh cache for: {}", id, error)
            );
    }

    private Mono<Data> loadAndCache(String id, String cacheKey) {
        return dataRepository.findById(id)
            .flatMap(data -> {
                CachedData cached = new CachedData(data, Instant.now());
                return redisTemplate.opsForValue()
                    .set(cacheKey, cached, CACHE_TTL)
                    .thenReturn(data);
            });
    }

    @Data
    @AllArgsConstructor
    public static class CachedData {
        private Data data;
        private Instant cachedAt;
    }
}
```

### Multi-Level Cache

```java
@Service
@RequiredArgsConstructor
public class MultiLevelCacheService {

    private final DataRepository dataRepository;
    private final ReactiveRedisTemplate<String, Data> redisTemplate;
    private final Cache<String, Data> localCache; // Caffeine cache

    private static final String REDIS_PREFIX = "data:";
    private static final Duration REDIS_TTL = Duration.ofHours(1);
    private static final Duration LOCAL_TTL = Duration.ofMinutes(5);

    public Mono<Data> getData(String id) {
        // L1: Check local cache
        Data localCached = localCache.getIfPresent(id);
        if (localCached != null) {
            return Mono.just(localCached);
        }

        String redisKey = REDIS_PREFIX + id;

        // L2: Check Redis
        return redisTemplate.opsForValue().get(redisKey)
            .doOnNext(data -> localCache.put(id, data)) // Populate L1
            .switchIfEmpty(
                // L3: Load from database
                dataRepository.findById(id)
                    .flatMap(data -> {
                        // Populate both caches
                        localCache.put(id, data);
                        return redisTemplate.opsForValue()
                            .set(redisKey, data, REDIS_TTL)
                            .thenReturn(data);
                    })
            );
    }

    public Mono<Void> invalidate(String id) {
        localCache.invalidate(id);
        return redisTemplate.delete(REDIS_PREFIX + id).then();
    }

    @Bean
    public Cache<String, Data> localCache() {
        return Caffeine.newBuilder()
            .maximumSize(10_000)
            .expireAfterWrite(LOCAL_TTL)
            .recordStats()
            .build();
    }
}
```
