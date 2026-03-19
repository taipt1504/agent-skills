# Spring Boot Production Defaults Reference

Production configuration patterns for Java 17+ / Spring Boot 3.x (both MVC and WebFlux).

## Table of Contents
- [Application Properties](#application-properties)
- [Caching with Redis](#caching-with-redis)
- [Async Processing](#async-processing)
- [Rate Limiting (Resilience4j)](#rate-limiting-resilience4j)
- [Transactional Best Practices](#transactional-best-practices)
- [Graceful Shutdown](#graceful-shutdown)
- [Actuator & Observability](#actuator--observability)
- [Error Handling (RFC 7807)](#error-handling-rfc-7807)

---

## Application Properties

### MVC Stack (Tomcat + JPA/Hibernate)

```yaml
spring:
  jackson:
    default-property-inclusion: non_null
    serialization:
      write-dates-as-timestamps: false
    deserialization:
      fail-on-unknown-properties: true
  datasource:
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      idle-timeout: 300000          # 5 min
      max-lifetime: 1800000         # 30 min
      connection-timeout: 30000     # 30 sec
      leak-detection-threshold: 60000
      pool-name: HikariPool
  jpa:
    open-in-view: false             # Prevent lazy loading in controllers
    properties:
      hibernate:
        default_batch_fetch_size: 16
        order_inserts: true
        order_updates: true
        jdbc:
          batch_size: 25

server:
  shutdown: graceful
  tomcat:
    connection-timeout: 5s
    max-threads: 200
    accept-count: 100

spring.lifecycle.timeout-per-shutdown-phase: 30s

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized
```

### WebFlux Stack (Netty + R2DBC)

```yaml
spring:
  jackson:
    default-property-inclusion: non_null
    serialization:
      write-dates-as-timestamps: false
    deserialization:
      fail-on-unknown-properties: true
  r2dbc:
    url: r2dbc:pool:postgresql://localhost:5432/mydb
    pool:
      initial-size: 10
      max-size: 50
      max-idle-time: 30m
      max-life-time: 60m
      max-acquire-time: 10s
      validation-query: SELECT 1
  reactor:
    context-propagation: auto

server:
  shutdown: graceful
  netty:
    connection-timeout: 10s
    max-keep-alive-requests: 10000
    idle-timeout: 60s

spring.lifecycle.timeout-per-shutdown-phase: 30s

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized
```

---

## Caching with Redis

### @Cacheable / @CacheEvict / @CachePut

```java
@Service
@RequiredArgsConstructor
public class ProductQueryService {

    private final ProductRepository productRepository;

    @Cacheable(value = "products", key = "#id", unless = "#result == null")
    public ProductDto findById(Long id) {
        return productRepository.findById(id)
            .map(this::toDto)
            .orElse(null);
    }

    @CacheEvict(value = "products", key = "#id")
    public void evict(Long id) {
        // Cache eviction only
    }

    @CachePut(value = "products", key = "#result.id")
    public ProductDto update(UpdateProductCommand command) {
        return toDto(productRepository.save(toEntity(command)));
    }
}
```

### Redis TTL Configuration

```java
@Configuration
@EnableCaching
public class CacheConfig {

    @Bean
    public RedisCacheManager cacheManager(RedisConnectionFactory factory) {
        var defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(30))
            .serializeValuesWith(SerializationPair.fromSerializer(
                new GenericJackson2JsonRedisSerializer()));

        var cacheConfigs = Map.of(
            "products", defaultConfig.entryTtl(Duration.ofHours(1)),
            "user-sessions", defaultConfig.entryTtl(Duration.ofMinutes(15))
        );

        return RedisCacheManager.builder(factory)
            .cacheDefaults(defaultConfig)
            .withInitialCacheConfigurations(cacheConfigs)
            .build();
    }
}
```

**Rules:**
- Always set TTL -- never cache indefinitely
- Use `unless = "#result == null"` to avoid caching null values
- `@CacheEvict` on write operations to prevent stale data
- Serialize with JSON (not Java serialization) for debuggability

---

## Async Processing

```java
@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean("taskExecutor")
    public TaskExecutor taskExecutor() {
        var executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);           // Active threads
        executor.setMaxPoolSize(8);            // Burst capacity
        executor.setQueueCapacity(100);        // Backlog before rejection
        executor.setThreadNamePrefix("async-");
        executor.setRejectedExecutionHandler(new CallerRunsPolicy());
        executor.initialize();
        return executor;
    }
}

@Service
@RequiredArgsConstructor
public class NotificationService {

    @Async("taskExecutor")
    public CompletableFuture<Void> sendEmailAsync(String to, String subject, String body) {
        emailClient.send(to, subject, body);
        return CompletableFuture.completedFuture(null);
    }
}
```

**Thread pool sizing:**
- `corePoolSize` = number of CPU cores
- `maxPoolSize` = 2x cores for IO-bound tasks
- `queueCapacity` = tune based on acceptable latency
- `CallerRunsPolicy` = graceful degradation (caller thread handles overflow)

---

## Rate Limiting (Resilience4j)

### Controller Integration

```java
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
public class OrderController {

    @RateLimiter(name = "createOrder", fallbackMethod = "rateLimitFallback")
    @PostMapping
    public OrderResponse createOrder(@Valid @RequestBody CreateOrderRequest request) {
        return createOrderUseCase.execute(request);
    }

    private OrderResponse rateLimitFallback(CreateOrderRequest request,
                                             RequestNotPermitted ex) {
        throw new TooManyRequestsException("Rate limit exceeded. Try again later.");
    }
}
```

### Configuration

```yaml
resilience4j:
  ratelimiter:
    instances:
      createOrder:
        limit-for-period: 10        # Max requests per period
        limit-refresh-period: 1s    # Reset interval
        timeout-duration: 0s        # Don't queue -- fail immediately
```

### Redis-based Rate Limiting (MVC Interceptor)

```java
@Component
@RequiredArgsConstructor
public class RateLimitInterceptor implements HandlerInterceptor {

    private final RedisTemplate<String, Integer> redisTemplate;
    private static final int MAX_REQUESTS_PER_MINUTE = 60;

    @Override
    public boolean preHandle(HttpServletRequest request,
                              HttpServletResponse response,
                              Object handler) throws Exception {
        String clientId = extractClientId(request);
        String key = "rate-limit:" + clientId + ":" + getCurrentMinuteBucket();

        Long count = redisTemplate.opsForValue().increment(key);
        if (count == 1) {
            redisTemplate.expire(key, Duration.ofMinutes(2));
        }

        if (count > MAX_REQUESTS_PER_MINUTE) {
            response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
            response.setHeader("X-RateLimit-Limit", String.valueOf(MAX_REQUESTS_PER_MINUTE));
            response.setHeader("X-RateLimit-Remaining", "0");
            response.setHeader("Retry-After", "60");
            return false;
        }

        response.setHeader("X-RateLimit-Remaining",
            String.valueOf(MAX_REQUESTS_PER_MINUTE - count));
        return true;
    }
}
```

---

## Transactional Best Practices

```java
// Read-only for queries (enables optimizations)
@Transactional(readOnly = true)
public OrderDto findById(Long id) { ... }

// Explicit timeout for writes
@Transactional(timeout = 10)
public OrderDto createOrder(CreateOrderCommand command) { ... }

// Reactive transaction (R2DBC)
@Transactional
public Mono<Order> createOrder(CreateOrderCommand cmd) {
    return orderRepository.save(toEntity(cmd))
        .flatMap(order -> inventoryRepository.decrementStock(
            cmd.productId(), cmd.quantity())
            .thenReturn(order));
}
```

**Rules:**
- `@Transactional(readOnly = true)` on all query methods
- Never on `private` methods (Spring proxy won't intercept)
- Never on entire class when only some methods need it
- Explicit timeout on write transactions
- For WebFlux: use `TransactionalOperator` when programmatic control needed

---

## Graceful Shutdown

```yaml
server:
  shutdown: graceful

spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

This ensures:
- No new requests accepted after SIGTERM
- In-flight requests complete within timeout
- Connections drain gracefully
- Background tasks complete

For custom cleanup:

```java
@Component
@RequiredArgsConstructor
public class GracefulShutdownHook implements DisposableBean {

    private final KafkaConsumer consumer;
    private final ScheduledExecutorService scheduler;

    @Override
    public void destroy() {
        consumer.close();
        scheduler.shutdown();
        try {
            scheduler.awaitTermination(10, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```

---

## Actuator & Observability

### Dependency

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

### Configuration

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true       # Kubernetes liveness/readiness
  metrics:
    tags:
      application: ${spring.application.name}
```

### Custom Metrics

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final MeterRegistry meterRegistry;

    public OrderDto createOrder(CreateOrderCommand command) {
        Timer.Sample sample = Timer.start(meterRegistry);
        try {
            OrderDto result = doCreate(command);
            meterRegistry.counter("orders.created",
                "status", result.status().name()).increment();
            return result;
        } finally {
            sample.stop(meterRegistry.timer("orders.create.duration"));
        }
    }
}
```

---

## Error Handling (RFC 7807)

### MVC (@RestControllerAdvice)

Use `@RestControllerAdvice` with `ProblemDetail` for standardized error responses:

- Domain exceptions -> 404/409/422
- `MethodArgumentNotValidException` -> 400 with field errors
- `ConstraintViolationException` -> 400
- `AccessDeniedException` -> 403
- Catch-all -> 500 (log stack, return generic message)

### WebFlux (GlobalErrorWebExceptionHandler)

```java
@Component
@Order(-2)
public class GlobalErrorWebExceptionHandler extends AbstractErrorWebExceptionHandler {
    // See spring-webflux.md reference for full implementation
}
```

**Rules:**
- Never expose internal details (stack traces, SQL) in error responses
- Always include a machine-readable error type
- Use `ProblemDetail` (Spring 6+) for RFC 7807 compliance
- Log the full error server-side with correlation ID
