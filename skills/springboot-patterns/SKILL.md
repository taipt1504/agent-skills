---
name: springboot-patterns
description: Spring Boot patterns — REST controllers, pagination, caching, async processing, rate limiting, production defaults
---

# Spring Boot Patterns

## When to Activate

- Building REST API controllers with Spring Boot
- Implementing pagination, caching, or async processing
- Configuring production defaults (HikariCP, Jackson, error handling)
- Reviewing Spring Boot application configuration

## REST Controller Patterns

```java
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
@Validated
public class OrderController {

    private final CreateOrderUseCase createOrderUseCase;
    private final GetOrderQuery getOrderQuery;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public OrderResponse createOrder(@Valid @RequestBody CreateOrderRequest request) {
        return createOrderUseCase.execute(request);
    }

    @GetMapping("/{id}")
    public OrderResponse getOrder(@PathVariable Long id) {
        return getOrderQuery.execute(id);
    }

    @GetMapping
    public Page<OrderSummary> listOrders(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "createdAt,desc") String[] sort) {
        return getOrderQuery.list(PageRequest.of(page, size, Sort.by(parseSortOrders(sort))));
    }
}
```

**Rules:**
- `@RequiredArgsConstructor` — constructor injection only
- `@Validated` on class — enables method-level validation
- `@Valid` on request body — triggers Bean Validation
- Use case / query objects — not calling service directly
- Return DTOs — never expose entities

## Pagination

### Offset-Based (Page<T>)

```java
// Controller
@GetMapping
public Page<OrderSummary> list(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") @Max(100) int size) {
    return orderQuery.list(PageRequest.of(page, Math.min(size, 100)));
}

// Response shape (auto-serialized by Spring)
// { "content": [...], "totalElements": 150, "totalPages": 8, "number": 0 }
```

### Cursor-Based (Slice<T>)

```java
// Controller — for infinite scroll / large datasets
@GetMapping("/feed")
public CursorResponse<OrderSummary> feed(
        @RequestParam(required = false) String cursor,
        @RequestParam(defaultValue = "20") @Max(100) int size) {
    Slice<OrderSummary> slice = orderQuery.findAfterCursor(cursor, size);
    String nextCursor = slice.hasNext()
        ? slice.getContent().get(slice.getContent().size() - 1).id().toString()
        : null;
    return new CursorResponse<>(slice.getContent(), nextCursor, slice.hasNext());
}

public record CursorResponse<T>(List<T> items, String nextCursor, boolean hasMore) {}
```

**Use `Page<T>`** when UI needs total count. **Use `Slice<T>`** for infinite scroll (avoids `COUNT(*)` query).

## Caching

### @Cacheable with Redis

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
        // Always updates cache after execution
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
        executor.setRejectedExecutionHandler(new CallerRunsPolicy()); // Graceful degradation
        executor.initialize();
        return executor;
    }
}

@Service
@RequiredArgsConstructor
public class NotificationService {

    @Async("taskExecutor")
    public CompletableFuture<Void> sendEmailAsync(String to, String subject, String body) {
        // Runs on separate thread pool
        emailClient.send(to, subject, body);
        return CompletableFuture.completedFuture(null);
    }
}
```

**Thread pool sizing:** `corePoolSize = CPU cores`, `maxPoolSize = 2x cores` for IO-bound tasks.

## Rate Limiting (Resilience4j)

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

    private OrderResponse rateLimitFallback(CreateOrderRequest request, RequestNotPermitted ex) {
        throw new TooManyRequestsException("Rate limit exceeded. Try again later.");
    }
}
```

```yaml
resilience4j:
  ratelimiter:
    instances:
      createOrder:
        limit-for-period: 10        # Max requests per period
        limit-refresh-period: 1s    # Reset interval
        timeout-duration: 0s        # Don't queue — fail immediately
```

## Production Defaults

### RFC 7807 Problem Details

Use `@RestControllerAdvice` with `ProblemDetail` for standardized error responses.
See `api-design` skill for full GlobalExceptionHandler pattern with domain exceptions and validation handling.

### Application Properties

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
      leak-detection-threshold: 60000
  jpa:
    open-in-view: false  # Prevent lazy loading in controllers
    properties:
      hibernate:
        default_batch_fetch_size: 16
        order_inserts: true
        order_updates: true

server:
  shutdown: graceful
  tomcat:
    connection-timeout: 5s

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
```

### Transactional Best Practices

```java
// GOOD: Read-only for queries
@Transactional(readOnly = true)
public OrderDto findById(Long id) { ... }

// GOOD: Explicit timeout
@Transactional(timeout = 10)
public OrderDto createOrder(CreateOrderCommand command) { ... }

// BAD: @Transactional on private methods (Spring proxy won't intercept)
// BAD: @Transactional on entire class when only some methods need it
```

## Verification Checklist

- [ ] Constructor injection with `@RequiredArgsConstructor` (no `@Autowired`)
- [ ] `@Validated` on controller class, `@Valid` on request bodies
- [ ] DTOs returned from controllers (never entities)
- [ ] Pagination with max size cap (e.g., `@Max(100)`)
- [ ] `@Transactional(readOnly = true)` on query methods
- [ ] `spring.jpa.open-in-view: false` in config
- [ ] RFC 7807 `ProblemDetail` for error responses
- [ ] Rate limiting on write endpoints
- [ ] Graceful shutdown configured
