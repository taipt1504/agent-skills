# R2DBC Configuration Reference

## Dependencies

### Maven

```xml
<dependencies>
    <!-- Spring Data R2DBC -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-r2dbc</artifactId>
    </dependency>

    <!-- PostgreSQL R2DBC Driver -->
    <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>r2dbc-postgresql</artifactId>
        <scope>runtime</scope>
    </dependency>

    <!-- Connection Pool -->
    <dependency>
        <groupId>io.r2dbc</groupId>
        <artifactId>r2dbc-pool</artifactId>
    </dependency>

    <!-- Metrics (optional) -->
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-registry-prometheus</artifactId>
    </dependency>
</dependencies>
```

### Gradle

```kotlin
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-data-r2dbc")
    runtimeOnly("org.postgresql:r2dbc-postgresql")
    implementation("io.r2dbc:r2dbc-pool")
    implementation("io.micrometer:micrometer-registry-prometheus")
}
```

---

## Application Configuration

### application.yml (Production)

```yaml
spring:
  r2dbc:
    url: r2dbc:pool:postgresql://localhost:5432/mydb
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    pool:
      initial-size: 10
      max-size: 50
      max-idle-time: 30m
      max-life-time: 1h
      max-acquire-time: 5s
      max-create-connection-time: 10s
      validation-query: SELECT 1

  # Enable SQL logging in dev
  logging:
    level:
      io.r2dbc.postgresql.QUERY: DEBUG
      io.r2dbc.postgresql.PARAM: TRACE
```

### Programmatic Configuration

```java
@Configuration
@EnableR2dbcRepositories
@EnableR2dbcAuditing
public class R2dbcConfiguration extends AbstractR2dbcConfiguration {

    @Value("${spring.r2dbc.url}")
    private String url;

    @Value("${spring.r2dbc.username}")
    private String username;

    @Value("${spring.r2dbc.password}")
    private String password;

    @Override
    @Bean
    public ConnectionFactory connectionFactory() {
        PostgresqlConnectionConfiguration pgConfig = PostgresqlConnectionConfiguration.builder()
            .host(extractHost(url))
            .port(extractPort(url))
            .database(extractDatabase(url))
            .username(username)
            .password(password)
            // PostgreSQL specific optimizations
            .preparedStatementCacheQueries(256)
            .tcpNoDelay(true)
            .tcpKeepAlive(true)
            .build();

        PostgresqlConnectionFactory connectionFactory =
            new PostgresqlConnectionFactory(pgConfig);

        ConnectionPoolConfiguration poolConfig = ConnectionPoolConfiguration.builder()
            .connectionFactory(connectionFactory)
            .name("pg-pool")
            .initialSize(10)
            .maxSize(50)
            .maxIdleTime(Duration.ofMinutes(30))
            .maxLifeTime(Duration.ofHours(1))
            .maxAcquireTime(Duration.ofSeconds(5))
            .maxCreateConnectionTime(Duration.ofSeconds(10))
            .acquireRetry(3)
            .validationQuery("SELECT 1")
            .validationDepth(ValidationDepth.LOCAL)
            .build();

        return new ConnectionPool(poolConfig);
    }

    @Bean
    public ReactiveTransactionManager transactionManager(ConnectionFactory connectionFactory) {
        return new R2dbcTransactionManager(connectionFactory);
    }

    @Bean
    public TransactionalOperator transactionalOperator(ReactiveTransactionManager txManager) {
        return TransactionalOperator.create(txManager);
    }

    @Bean
    public R2dbcEntityTemplate r2dbcEntityTemplate(ConnectionFactory connectionFactory) {
        return new R2dbcEntityTemplate(connectionFactory);
    }
}
```

---

## Connection Pool Sizing Guide

### Formulas

```
max_connections = (core_count * 2) + effective_spindle_count
```

Cho SSD:
```
max_connections = (CPU cores * 2) + 1
```

### Recommended Settings by Load

| Load Level | Initial | Max | Max Idle Time |
|------------|---------|-----|---------------|
| Low (< 100 RPS) | 5 | 20 | 10m |
| Medium (100-1000 RPS) | 10 | 50 | 30m |
| High (> 1000 RPS) | 20 | 100 | 1h |

### PostgreSQL max_connections

Đảm bảo PostgreSQL có đủ connections:
```sql
-- Check current setting
SHOW max_connections;

-- Recommended: app_pool_max * number_of_instances + buffer
-- Ví dụ: 50 * 3 + 10 = 160
ALTER SYSTEM SET max_connections = 200;
```

---

## SSL Configuration

### application.yml

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://localhost:5432/mydb?sslMode=verify-full&sslRootCert=/path/to/ca.crt
```

### Programmatic

```java
PostgresqlConnectionConfiguration.builder()
    .host("localhost")
    .port(5432)
    .database("mydb")
    .username("user")
    .password("password")
    .sslMode(SSLMode.VERIFY_FULL)
    .sslRootCert("/path/to/ca.crt")
    .build();
```

---

## Custom Converters

```java
@Configuration
public class R2dbcConverterConfig extends AbstractR2dbcConfiguration {

    @Override
    protected List<Object> getCustomConverters() {
        return List.of(
            new JsonToMapConverter(),
            new MapToJsonConverter(),
            new InstantToTimestampConverter()
        );
    }

    @ReadingConverter
    static class JsonToMapConverter implements Converter<Json, Map<String, Object>> {
        private final ObjectMapper mapper = new ObjectMapper();

        @Override
        public Map<String, Object> convert(Json source) {
            try {
                return mapper.readValue(source.asString(),
                    new TypeReference<Map<String, Object>>() {});
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }
    }

    @WritingConverter
    static class MapToJsonConverter implements Converter<Map<String, Object>, Json> {
        private final ObjectMapper mapper = new ObjectMapper();

        @Override
        public Json convert(Map<String, Object> source) {
            try {
                return Json.of(mapper.writeValueAsString(source));
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }
    }
}
```

---

## Health Check

```java
@Component
public class R2dbcHealthIndicator implements ReactiveHealthIndicator {

    private final ConnectionFactory connectionFactory;

    @Override
    public Mono<Health> health() {
        return Mono.from(connectionFactory.create())
            .flatMap(connection ->
                Mono.from(connection.createStatement("SELECT 1").execute())
                    .flatMap(result -> Mono.from(result.getRowsUpdated()))
                    .doFinally(signal -> connection.close().subscribe())
            )
            .map(rows -> Health.up().withDetail("database", "PostgreSQL").build())
            .onErrorResume(e -> Mono.just(
                Health.down().withException(e).build()
            ))
            .timeout(Duration.ofSeconds(5));
    }
}
```

---

## External Links

- [R2DBC PostgreSQL Driver](https://github.com/pgjdbc/r2dbc-postgresql)
- [R2DBC Pool](https://github.com/r2dbc/r2dbc-pool)
- [Spring Data R2DBC Reference](https://docs.spring.io/spring-data/r2dbc/reference/)
- [PostgreSQL Connection Tuning](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server)
