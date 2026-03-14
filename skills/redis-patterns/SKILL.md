---
name: redis-patterns
description: >
  Redis patterns for Java Spring WebFlux applications. Covers reactive Redis with
  Lettuce, caching strategies (cache-aside, write-through, write-behind), distributed
  locking with Redisson, rate limiting, Pub/Sub, Redis Streams, data structure selection,
  key design, serialization, cluster/sentinel, and testing. Use when implementing
  Redis in Spring Boot 3.x reactive projects.
---

# Redis Patterns for Spring WebFlux

Production-ready Redis patterns for Java 17+ / Spring Boot 3.x reactive applications.

## Dependencies

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-redis-reactive</artifactId>
</dependency>
<!-- Distributed locking, advanced features -->
<dependency>
    <groupId>org.redisson</groupId>
    <artifactId>redisson-spring-boot-starter</artifactId>
    <version>3.27.0</version>
</dependency>
```

## Configuration

```yaml
spring:
  data:
    redis:
      host: localhost
      port: 6379
      password: ${REDIS_PASSWORD:}
      timeout: 2000ms
      lettuce:
        pool:
          max-active: 16
          max-idle: 8
          min-idle: 4
          max-wait: 2000ms
```

## ReactiveRedisTemplate Setup

```java
@Configuration
public class RedisConfig {
    @Bean
    public ReactiveRedisTemplate<String, Object> reactiveRedisTemplate(
            ReactiveRedisConnectionFactory factory) {
        Jackson2JsonRedisSerializer<Object> serializer =
            new Jackson2JsonRedisSerializer<>(objectMapper(), Object.class);
        RedisSerializationContext<String, Object> context =
            RedisSerializationContext.<String, Object>newSerializationContext(new StringRedisSerializer())
                .value(serializer).hashKey(new StringRedisSerializer()).hashValue(serializer).build();
        return new ReactiveRedisTemplate<>(factory, context);
    }
}
```

## Caching Patterns

### Cache-Aside (Most Common)

```java
public Mono<UserProfile> getUserById(String userId) {
    String cacheKey = "user:profile:" + userId;
    return redisTemplate.opsForValue().get(cacheKey)
        .cast(UserProfile.class)
        .switchIfEmpty(Mono.defer(() ->
            userRepository.findById(userId)
                .flatMap(user -> redisTemplate.opsForValue()
                    .set(cacheKey, user, Duration.ofMinutes(30)).thenReturn(user))));
}

// Invalidate on write
public Mono<UserProfile> updateUser(String userId, UserProfile updated) {
    return userRepository.save(updated)
        .flatMap(saved -> redisTemplate.delete("user:profile:" + userId).thenReturn(saved));
}
```

### Write-Through

```java
public Mono<UserProfile> save(UserProfile user) {
    return userRepository.save(user)
        .flatMap(saved -> redisTemplate.opsForValue()
            .set("user:profile:" + saved.id(), saved, Duration.ofMinutes(30)).thenReturn(saved));
}
```

## Distributed Locking (Redisson — Recommended)

```java
@Service @RequiredArgsConstructor
public class RedissonLockService {
    private final RedissonClient redissonClient;

    public <T> Mono<T> executeWithLock(String resourceId, Duration waitTime, Duration leaseTime, Mono<T> task) {
        RLockReactive lock = redissonClient.reactive().getLock("lock:" + resourceId);
        return lock.tryLock(waitTime.toMillis(), leaseTime.toMillis(), TimeUnit.MILLISECONDS)
            .flatMap(acquired -> {
                if (!acquired) return Mono.error(new LockAcquisitionException("Lock unavailable: " + resourceId));
                return task.doFinally(signal -> lock.unlock().subscribe());
            });
    }
}
```

## Rate Limiting (Sliding Window)

```java
// Lua script-based sliding window — atomic
public Mono<RateLimitResult> isAllowed(String clientId, int maxRequests, Duration window) {
    String key = "ratelimit:" + clientId;
    long now = Instant.now().toEpochMilli();
    // ... see references/advanced-patterns.md for full implementation
    return redisTemplate.execute(RedisScript.of(luaScript, List.class), List.of(key), args)
        .next().map(result -> new RateLimitResult(result.get(0) == 1, result.get(1).intValue()));
}
```

## Data Structure Selection

| Structure | Use Case | Example |
|-----------|----------|---------|
| **String** | Key-value, counters, tokens | Session tokens, feature flags |
| **Hash** | Object storage, partial updates | User profiles |
| **Set** | Unique collections, membership | Online users, tags |
| **Sorted Set** | Rankings, sliding window rate limits | Leaderboards |
| **HyperLogLog** | Cardinality estimation (~0.81% error) | Unique visitor counts |
| **Stream** | Durable event log, consumer groups | Audit log, event sourcing |

## Key Naming Convention

```
{service}:{entity}:{id}          →  user:profile:12345
cache:{entity}:{id}              →  cache:product:SKU-100
lock:{entity}:{id}               →  lock:order:ORD-001
ratelimit:{api}:{clientId}       →  ratelimit:api:192.168.1.1
leaderboard:{board}:{date}       →  leaderboard:daily:2024-01-15
stream:{entity}                  →  stream:orders
```

## TTL Strategies

| Strategy | TTL | Use Case |
|----------|-----|----------|
| Fixed | 30 min | API responses, computed values |
| Sliding | Refresh on access | User sessions |
| Event-driven | Invalidate on write | Product catalog, user profiles |
| Jittered | base ± random(0-5min) | Prevents thundering herd |

```java
// Always set TTL — never leave keys without expiry
redisTemplate.opsForValue().set(key, value, Duration.ofMinutes(30));

// Jittered TTL
Duration jittered = Duration.ofMinutes(30).plus(Duration.ofSeconds(ThreadLocalRandom.current().nextInt(300)));
```

## Anti-Patterns

```
❌ No TTL on cache keys          → memory leak until OOM
❌ KEYS * in production          → O(N) blocks Redis; use SCAN instead
❌ Big keys (>1MB)               → split into individual keys or hash fields
❌ Hot keys (single counter)     → shard: "counter:" + (hash % 16), sum on read
❌ No cache stampede protection  → use Redisson lock on cache miss (thundering herd)
❌ Storing PII without encryption → encrypt sensitive fields before storing
```

## References

Load as needed:

- **[references/caching.md](references/caching.md)** — Write-behind, Spring Cache abstraction, reactive @Cacheable with AOP, eviction policies
- **[references/advanced-patterns.md](references/advanced-patterns.md)** — Full rate limiter (Lua script), Pub/Sub + SSE integration, Redis Streams with consumer groups
- **[references/data-structures.md](references/data-structures.md)** — Hash/Set/SortedSet/HyperLogLog patterns, leaderboard, Kryo/Protobuf serialization
- **[references/cluster-testing.md](references/cluster-testing.md)** — Sentinel/Cluster config, cluster-aware key design, session management, Testcontainers testing
