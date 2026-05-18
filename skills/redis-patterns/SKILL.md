---
name: redis-patterns
description: Redis patterns for Java Spring Boot (MVC and WebFlux) — reactive caching, distributed locking, rate limiting with Redis, Lua scripts, pub/sub, and cluster configuration. Use when implementing Redis-based caching, distributed locks, rate limiting, session storage, or any Redis data structure operations in Spring Boot applications.
triggers:
  natural: ["redis cache", "distributed lock", "rate limit with redis", "cache eviction"]
  code: ["ReactiveRedisTemplate", "@Cacheable", "RedisTemplate", "Redisson"]
applicability:
  always: false
  triggers:
    files_match: ["**/*Cache*.java", "**/*Lock*.java", "**/*RateLimit*.java", "**/*Redis*.java"]
    code_patterns: ["RedisTemplate", "ReactiveRedisTemplate", "Lettuce", "Redisson", "@Cacheable", "@CacheEvict"]
    task_keywords: ["Redis", "cache", "distributed lock", "Lua script", "rate limit", "session store", "TTL"]
    related_rules:
      - rules/java/observability.md
relevance_assessment: |
  HIGH 80%+: new cache layer, distributed lock, Redis-backed rate limiter
  MEDIUM 40-79%: cache invalidation tweak, TTL change, key naming refactor
  LOW 1-39%: service that uses cache, no Redis code touched
  ZERO: project has no Redis (verify: grep -r 'redis' build.gradle = 0)
---

# Redis Patterns for Spring Boot

## Cache Consistency Checklist

- [ ] TTL on all cache entries (no infinite caches)
- [ ] Cache eviction on write/update/delete
- [ ] Cache key includes version or tenant if multi-tenant
- [ ] Null values handled (`unless = "#result == null"`)
- [ ] Serializer configured explicitly (JSON, not Java serialization)
- [ ] Connection pool sized (Lettuce pool config)
- [ ] Redis Sentinel or Cluster for HA in production

## ReactiveRedisTemplate Config

```java
@Bean
public ReactiveRedisTemplate<String, Object> reactiveRedisTemplate(
        ReactiveRedisConnectionFactory factory) {
    var serializer = new Jackson2JsonRedisSerializer<>(objectMapper(), Object.class);
    var context = RedisSerializationContext.<String, Object>newSerializationContext(
            new StringRedisSerializer())
        .value(serializer).hashKey(new StringRedisSerializer())
        .hashValue(serializer).build();
    return new ReactiveRedisTemplate<>(factory, context);
}
```

## Cache-Aside Pattern

```java
public Mono<UserProfile> getUserById(String userId) {
    String key = "user:profile:" + userId;
    return redisTemplate.opsForValue().get(key).cast(UserProfile.class)
        .switchIfEmpty(Mono.defer(() -> userRepository.findById(userId)
            .flatMap(u -> redisTemplate.opsForValue()
                .set(key, u, Duration.ofMinutes(30)).thenReturn(u))));
}
// Invalidate on write
public Mono<UserProfile> updateUser(String userId, UserProfile updated) {
    return userRepository.save(updated)
        .flatMap(saved -> redisTemplate.delete("user:profile:" + userId).thenReturn(saved));
}
```

## Distributed Locking (Redisson)

```java
public <T> Mono<T> executeWithLock(String resourceId, Duration wait, Duration lease, Mono<T> task) {
    RLockReactive lock = redissonClient.reactive().getLock("lock:" + resourceId);
    return Mono.usingWhen(
        lock.tryLock(wait.toMillis(), lease.toMillis(), TimeUnit.MILLISECONDS)
            .flatMap(acquired -> acquired
                ? Mono.just(lock)
                : Mono.error(new LockAcquisitionException(resourceId))),
        acquired -> task,
        acquired -> acquired.unlock()
    );
}
```

## Data Structure Selection

| Structure | Use Case | Example |
|-----------|----------|---------|
| String | Counters, tokens | Session tokens, flags |
| Hash | Object storage | User profiles |
| Set | Unique collections | Online users, tags |
| Sorted Set | Rankings, rate limits | Leaderboards |
| HyperLogLog | Cardinality (~0.81% error) | Unique visitors |
| Stream | Durable event log | Audit, event sourcing |

## Key Naming & TTL

```
{service}:{entity}:{id}     → user:profile:12345
cache:{entity}:{id}          → cache:product:SKU-100
lock:{entity}:{id}           → lock:order:ORD-001
```

| Strategy | TTL | Use Case |
|----------|-----|----------|
| Fixed | 30 min | API responses |
| Sliding | Refresh on access | Sessions |
| Event-driven | Invalidate on write | Catalog |
| Jittered | base +/- random | Prevents thundering herd |

## Anti-Patterns

- No TTL → memory leak. Always set expiry.
- `KEYS *` in production → use `SCAN`.
- Big keys (>1MB) → split into hash fields.
- Hot keys → shard with suffix, sum on read.
- No stampede protection → lock on cache miss.

## References

- **[references/caching.md](references/caching.md)** — Write-behind, Spring Cache, reactive @Cacheable AOP, eviction, bulk ops
- **[references/advanced-patterns.md](references/advanced-patterns.md)** — Rate limiter (Lua), Pub/Sub + SSE, Redis Streams, consumer groups
- **[references/data-structures.md](references/data-structures.md)** — Hash/Set/SortedSet/HyperLogLog patterns, leaderboard, serialization
- **[references/cluster-testing.md](references/cluster-testing.md)** — Sentinel/Cluster config, hash tags, session management, Testcontainers

## Related Skills

- **summer-ratelimit** — Summer Framework rate limiting backed by Redis
- **spring-webflux-patterns** — WebFlux reactive chains that consume Redis caching
- **database-patterns** — Cache-aside pattern complements DB queries
- **testing-workflow** — Testcontainers for Redis integration tests
