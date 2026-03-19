# Redis Caching Reference

Write-behind, Spring Cache abstraction, and reactive @Cacheable patterns.

## Table of Contents
- [Cache-Aside (Read-Through)](#cache-aside-read-through)
- [Write-Behind (Async)](#write-behind-async)
- [Write-Through (Sync)](#write-through-sync)
- [Spring Cache Abstraction](#spring-cache-abstraction)
- [Reactive Cacheable Custom AOP](#reactive-cacheable-custom-aop)
- [Cache Stampede Prevention](#cache-stampede-prevention)
- [Bulk Cache Operations](#bulk-cache-operations)

---

## Cache-Aside (Read-Through)

```java
@Service @RequiredArgsConstructor
public class ProductCacheService {
    private final ReactiveRedisTemplate<String, Product> redisTemplate;
    private final ProductRepository productRepository;
    private static final Duration TTL = Duration.ofMinutes(30);

    public Mono<Product> findById(String productId) {
        String key = "product:" + productId;
        return redisTemplate.opsForValue().get(key)
            .switchIfEmpty(Mono.defer(() ->
                productRepository.findById(productId)
                    .flatMap(product ->
                        redisTemplate.opsForValue().set(key, product, TTL)
                            .thenReturn(product))
                    .switchIfEmpty(Mono.error(new NotFoundException("Product not found: " + productId)))
            ));
    }

    public Mono<Void> evict(String productId) {
        return redisTemplate.delete("product:" + productId).then();
    }

    // Cache with tags for bulk eviction
    public Mono<Product> findByCategoryWithTag(String productId, String categoryId) {
        String key = "product:" + productId;
        String tagKey = "product:category:" + categoryId;

        return redisTemplate.opsForValue().get(key)
            .switchIfEmpty(Mono.defer(() ->
                productRepository.findById(productId)
                    .flatMap(product -> Mono.zip(
                        redisTemplate.opsForValue().set(key, product, TTL),
                        redisTemplate.opsForSet().add(tagKey, productId)
                    ).thenReturn(product))
            ));
    }

    // Evict all in category
    public Mono<Void> evictCategory(String categoryId) {
        String tagKey = "product:category:" + categoryId;
        return redisTemplate.opsForSet().members(tagKey)
            .collectList()
            .flatMap(productIds -> {
                List<String> keys = productIds.stream()
                    .map(id -> "product:" + id).collect(Collectors.toList());
                keys.add(tagKey);
                return redisTemplate.delete(keys.toArray(new String[0])).then();
            });
    }
}
```

---

## Write-Behind (Async)

Write to cache immediately; persist to DB asynchronously.

```java
@Service @RequiredArgsConstructor @Slf4j
public class WriteBehindCacheService {
    private final ReactiveRedisTemplate<String, Product> redisTemplate;
    private final ProductRepository productRepository;
    private final Sinks.Many<Product> pendingWrites = Sinks.many().unicast().onBackpressureBuffer();

    @PostConstruct
    public void startWriteBehind() {
        pendingWrites.asFlux()
            .bufferTimeout(100, Duration.ofSeconds(1))  // batch writes
            .flatMap(batch ->
                Flux.fromIterable(batch)
                    .flatMap(productRepository::save)
                    .then()
                    .doOnError(ex -> log.error("Write-behind batch failed", ex))
                    .onErrorResume(ex -> Mono.empty()))
            .subscribe();
    }

    public Mono<Product> update(Product product) {
        String key = "product:" + product.id();
        return redisTemplate.opsForValue().set(key, product, Duration.ofMinutes(30))
            .doOnSuccess(v -> pendingWrites.tryEmitNext(product))  // async DB write
            .thenReturn(product);
    }
}
```

> **Caution:** Write-behind trades durability for performance. On cache failure before DB write, data is lost. Use only for non-critical or reconstructable data.

---

## Write-Through (Sync)

Write to cache and DB atomically.

```java
@Service @RequiredArgsConstructor
public class WriteThroughCacheService {
    private final ReactiveRedisTemplate<String, Product> redisTemplate;
    private final ProductRepository productRepository;

    @Transactional  // DB transaction
    public Mono<Product> save(Product product) {
        return productRepository.save(product)
            .flatMap(saved -> {
                String key = "product:" + saved.id();
                return redisTemplate.opsForValue().set(key, saved, Duration.ofMinutes(30))
                    .thenReturn(saved);
            });
    }
}
```

---

## Spring Cache Abstraction

Integrates with Spring `@Cacheable`, `@CacheEvict`, and `@CachePut`. Works with **blocking** (imperative) code.

```java
@Configuration
public class RedisCacheConfig {
    @Bean
    public RedisCacheManager cacheManager(RedisConnectionFactory factory) {
        RedisCacheConfiguration config = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(30))
            .serializeKeysWith(RedisSerializationContext.SerializationPair
                .fromSerializer(new StringRedisSerializer()))
            .serializeValuesWith(RedisSerializationContext.SerializationPair
                .fromSerializer(new GenericJackson2JsonRedisSerializer()))
            .disableCachingNullValues();

        // Per-cache TTL overrides
        Map<String, RedisCacheConfiguration> overrides = Map.of(
            "products", config.entryTtl(Duration.ofHours(1)),
            "users", config.entryTtl(Duration.ofMinutes(15)),
            "sessions", config.entryTtl(Duration.ofDays(1))
        );

        return RedisCacheManager.builder(factory)
            .cacheDefaults(config)
            .withInitialCacheConfigurations(overrides)
            .transactionAware()
            .build();
    }
}

// Service usage (imperative/blocking only)
@Service
@CacheConfig(cacheNames = "products")
public class ProductService {
    @Cacheable(key = "#productId")
    public Product findById(String productId) {
        return productRepository.findById(productId).orElseThrow();
    }

    @CacheEvict(key = "#product.id")
    public Product update(Product product) {
        return productRepository.save(product);
    }

    @CacheEvict(allEntries = true)
    public void evictAll() {}

    @CachePut(key = "#result.id")
    public Product create(Product product) {
        return productRepository.save(product);
    }
}
```

> **Note:** Spring's `@Cacheable` does NOT work with reactive `Mono/Flux` returns. Use manual cache-aside pattern or the custom AOP below for reactive services.

---

## Reactive Cacheable Custom AOP

```java
@Aspect
@Component @RequiredArgsConstructor
public class ReactiveCacheAspect {
    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;

    @Around("@annotation(reactiveCacheable)")
    public Object cache(ProceedingJoinPoint pjp, ReactiveCacheable reactiveCacheable) throws Throwable {
        String key = resolveKey(reactiveCacheable.key(), pjp);
        Duration ttl = Duration.ofSeconds(reactiveCacheable.ttlSeconds());

        Mono<?> result = (Mono<?>) pjp.proceed();

        return redisTemplate.opsForValue().get(key)
            .switchIfEmpty(Mono.defer(() -> result
                .flatMap(value ->
                    redisTemplate.opsForValue().set(key, serialize(value), ttl)
                        .thenReturn(value))));
    }
}

@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface ReactiveCacheable {
    String key();
    long ttlSeconds() default 1800;
}

// Usage
@ReactiveCacheable(key = "'product:' + #productId", ttlSeconds = 3600)
public Mono<Product> findById(String productId) {
    return productRepository.findById(productId);
}
```

---

## Cache Stampede Prevention

When cache expires, prevent multiple simultaneous DB loads.

```java
@Service @RequiredArgsConstructor
public class StampedeProtectedCache {
    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private final ConcurrentHashMap<String, Mono<?>> inFlightRequests = new ConcurrentHashMap<>();

    @SuppressWarnings("unchecked")
    public <T> Mono<T> getOrLoad(String key, Mono<T> loader, Duration ttl) {
        return (Mono<T>) redisTemplate.opsForValue().get(key)
            .switchIfEmpty(Mono.defer(() ->
                (Mono<T>) inFlightRequests.computeIfAbsent(key, k ->
                    loader
                        .flatMap(value ->
                            redisTemplate.opsForValue().set(key, value, ttl)
                                .thenReturn(value))
                        .doFinally(signal -> inFlightRequests.remove(key))
                        .cache()  // ← share single subscription for concurrent requests
                )
            ));
    }
}
```

---

## Bulk Cache Operations

```java
@Service @RequiredArgsConstructor
public class BulkCacheService {
    private final ReactiveRedisTemplate<String, Product> redisTemplate;

    // Multi-get (pipeline)
    public Mono<Map<String, Product>> multiGet(List<String> productIds) {
        List<String> keys = productIds.stream()
            .map(id -> "product:" + id).toList();
        return redisTemplate.opsForValue().multiGet(keys)
            .map(values -> {
                Map<String, Product> result = new HashMap<>();
                for (int i = 0; i < productIds.size(); i++) {
                    if (values.get(i) != null)
                        result.put(productIds.get(i), values.get(i));
                }
                return result;
            });
    }

    // Multi-set
    public Mono<Void> multiSet(Map<String, Product> products) {
        Map<String, Product> keyed = products.entrySet().stream()
            .collect(Collectors.toMap(e -> "product:" + e.getKey(), Map.Entry::getValue));
        return redisTemplate.opsForValue().multiSet(keyed).then();
    }

    // Cache warm-up on startup
    @EventListener(ApplicationReadyEvent.class)
    public void warmUpCache() {
        productRepository.findTop100ByOrderByViewCountDesc()
            .flatMap(product ->
                redisTemplate.opsForValue().set(
                    "product:" + product.id(), product, Duration.ofHours(1)))
            .subscribe(r -> log.debug("Cache warmed"), ex -> log.error("Warm-up failed", ex));
    }
}
```
