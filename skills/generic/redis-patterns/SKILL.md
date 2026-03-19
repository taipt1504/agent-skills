---
name: redis-patterns
description: >
  Redis patterns for Java Spring WebFlux — reactive caching, distributed locking, rate limiting,
  data structure selection, key design, TTL strategies, and anti-patterns.
triggers:
  - Redis
  - ReactiveRedisTemplate
  - cache
  - Redisson
  - rate limiting
  - Pub/Sub
  - Redis Streams
---

# Redis Patterns for Spring WebFlux

## When to Activate

- Implementing caching with `ReactiveRedisTemplate`
- Building distributed locks or rate limiters
- Configuring Redis connections and TTL policies
- Reviewing cache consistency and invalidation

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
    return lock.tryLock(wait.toMillis(), lease.toMillis(), TimeUnit.MILLISECONDS)
        .flatMap(acquired -> {
            if (!acquired) return Mono.error(new LockAcquisitionException(resourceId));
            return task.doFinally(signal -> lock.unlock().subscribe());
        });
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

- No TTL on keys -> memory leak. Always set expiry.
- `KEYS *` in production -> use `SCAN` instead.
- Big keys (>1MB) -> split into hash fields.
- Hot keys -> shard with suffix, sum on read.
- No stampede protection -> lock on cache miss.

## References

- **[references/caching.md](references/caching.md)** — Write-behind, Spring Cache, reactive @Cacheable AOP, eviction, bulk ops
- **[references/advanced-patterns.md](references/advanced-patterns.md)** — Rate limiter (Lua), Pub/Sub + SSE, Redis Streams, consumer groups
- **[references/data-structures.md](references/data-structures.md)** — Hash/Set/SortedSet/HyperLogLog patterns, leaderboard, serialization
- **[references/cluster-testing.md](references/cluster-testing.md)** — Sentinel/Cluster config, hash tags, session management, Testcontainers
