# Redis Cluster, Sentinel & Testing Reference

Sentinel config, Cluster config, session management, Testcontainers, and anti-patterns.

## Table of Contents
- [Sentinel Configuration](#sentinel-configuration)
- [Cluster Configuration](#cluster-configuration)
- [Cluster-Aware Key Design (Hash Tags)](#cluster-aware-key-design-hash-tags)
- [Session Management](#session-management)
- [Testcontainers Testing](#testcontainers-testing)
- [Anti-Patterns](#anti-patterns)

---

## Sentinel Configuration

Use for high availability with automatic failover (single shard, multiple replicas).

```yaml
spring:
  redis:
    sentinel:
      master: mymaster
      nodes:
        - sentinel-1:26379
        - sentinel-2:26379
        - sentinel-3:26379
      password: ${SENTINEL_PASSWORD}
    password: ${REDIS_PASSWORD}
    lettuce:
      pool:
        max-active: 50
        max-idle: 20
        min-idle: 5
        max-wait: 5s
      sentinel:
        read-from: REPLICA  # read from replicas to distribute load
```

```java
@Configuration
public class RedisSentinelConfig {
    @Bean
    public LettuceConnectionFactory redisConnectionFactory(RedisProperties props) {
        RedisSentinelConfiguration sentinelConfig = new RedisSentinelConfiguration(
            props.getSentinel().getMaster(),
            new HashSet<>(props.getSentinel().getNodes().stream()
                .map(node -> {
                    String[] parts = node.split(":");
                    return new RedisNode(parts[0], Integer.parseInt(parts[1]));
                }).collect(Collectors.toSet())));
        sentinelConfig.setPassword(props.getPassword());

        LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
            .readFrom(ReadFrom.REPLICA_PREFERRED)
            .build();

        return new LettuceConnectionFactory(sentinelConfig, clientConfig);
    }
}
```

---

## Cluster Configuration

Use for horizontal scaling across multiple shards.

```yaml
spring:
  redis:
    cluster:
      nodes:
        - redis-cluster-1:6379
        - redis-cluster-2:6379
        - redis-cluster-3:6379
      max-redirects: 3
    password: ${REDIS_PASSWORD}
    lettuce:
      cluster:
        refresh:
          adaptive: true          # auto-detect topology changes
          period: 30s
      pool:
        max-active: 100
        max-idle: 30
```

```java
@Configuration
public class RedisClusterConfig {
    @Bean
    public LettuceConnectionFactory redisConnectionFactory(RedisProperties props) {
        RedisClusterConfiguration clusterConfig = new RedisClusterConfiguration(
            props.getCluster().getNodes());
        clusterConfig.setPassword(props.getPassword());
        clusterConfig.setMaxRedirects(props.getCluster().getMaxRedirects());

        ClusterTopologyRefreshOptions refreshOptions = ClusterTopologyRefreshOptions.builder()
            .adaptiveRefreshTriggersTimeout(Duration.ofSeconds(5))
            .enableAllAdaptiveRefreshTriggers()
            .build();

        ClusterClientOptions clientOptions = ClusterClientOptions.builder()
            .topologyRefreshOptions(refreshOptions)
            .validateClusterNodeMembership(false)
            .build();

        LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
            .clientOptions(clientOptions)
            .readFrom(ReadFrom.REPLICA_PREFERRED)
            .build();

        return new LettuceConnectionFactory(clusterConfig, clientConfig);
    }
}
```

---

## Cluster-Aware Key Design (Hash Tags)

In cluster mode, keys with the same hash tag `{tag}` are guaranteed to be on the same node. Required for multi-key operations (MGET, transactions, Lua scripts).

```java
// WRONG — different nodes in cluster, MGET will fail
"user:123"       // → node A
"session:123"    // → node B

// CORRECT — same hash tag, same node
"user:{u123}"
"session:{u123}"
"orders:{u123}:*"

// CORRECT — rate limiter key with hash tag
String key = "ratelimit:{" + clientId + "}";

// CORRECT — distributed lock with hash tag
String lockKey = "lock:{resource-id-123}";

// Key naming with hash tags
public String userKey(String userId) { return "user:{" + userId + "}"; }
public String sessionKey(String userId) { return "session:{" + userId + "}"; }
public String ordersKey(String userId) { return "orders:{" + userId + "}"; }
```

---

## Session Management

```java
// Dependencies
// spring-session-data-redis

@Configuration
@EnableRedisWebSession(maxInactiveIntervalInSeconds = 3600)
public class SessionConfig {
    // Spring auto-configures; just enable
}

// Custom session config
@Configuration
public class CustomSessionConfig implements WebFluxConfigurer {
    @Bean
    public ReactiveSessionRepository<MapSession> reactiveSessionRepository(
            ReactiveRedisTemplate<String, Object> redisTemplate) {
        var repo = new ReactiveRedisSessionRepository(redisTemplate);
        repo.setDefaultMaxInactiveInterval(Duration.ofHours(1));
        return repo;
    }
}

// Access session in controller
@GetMapping("/api/profile")
public Mono<UserProfile> getProfile(WebSession session) {
    String userId = session.getAttribute("userId");
    return userService.findById(userId);
}

// Store in session
@PostMapping("/api/login")
public Mono<LoginResponse> login(@RequestBody LoginRequest request, WebSession session) {
    return authService.authenticate(request)
        .doOnSuccess(user -> {
            session.getAttributes().put("userId", user.id());
            session.getAttributes().put("roles", user.roles());
        })
        .map(user -> new LoginResponse(user.id(), "Login successful"));
}
```

---

## Testcontainers Testing

```java
@SpringBootTest
@Testcontainers
class RedisIntegrationTest {

    @Container
    static RedisContainer redis = new RedisContainer(
        DockerImageName.parse("redis:7-alpine"))
        .withExposedPorts(6379);

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.redis.host", redis::getHost);
        registry.add("spring.redis.port", () -> redis.getMappedPort(6379));
    }

    @Autowired
    private ReactiveRedisTemplate<String, String> redisTemplate;

    @Test
    void shouldSetAndGetValue() {
        StepVerifier.create(
            redisTemplate.opsForValue().set("key", "value", Duration.ofMinutes(1))
                .then(redisTemplate.opsForValue().get("key")))
            .expectNext("value")
            .verifyComplete();
    }

    @Test
    void shouldExpire() {
        StepVerifier.create(
            redisTemplate.opsForValue().set("expiring-key", "value", Duration.ofMillis(100))
                .then(Mono.delay(Duration.ofMillis(200)))
                .then(redisTemplate.opsForValue().get("expiring-key")))
            .verifyComplete();  // empty Mono — key expired
    }
}

// Cluster test
@SpringBootTest
@Testcontainers
class RedisClusterTest {
    @Container
    static RedisClusterContainer cluster = new RedisClusterContainer(
        DockerImageName.parse("grokzen/redis-cluster:7.0.10"))
        .withExposedPorts(7000, 7001, 7002, 7003, 7004, 7005);

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("spring.redis.cluster.nodes", () ->
            cluster.getMappedPort(7000) + "," + cluster.getMappedPort(7001));
    }
}
```

---

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Big Keys** | Single key > 10MB causes latency spikes, blocks main thread | Split into smaller keys or use Redis Streams |
| **Hot Keys** | Single key > 10K ops/sec; saturates one node | Hash key with suffix, use local cache, read from replicas |
| **Thundering Herd** | Mass cache expiry at same time causes DB spike | Stagger TTL with jitter: `ttl + random(0, ttl * 0.1)` |
| **Key Explosion** | Millions of unique keys without TTL | Always set TTL; use patterns for eviction policy |
| **Multi-key ops without hash tags** | MGET/MSET fails in cluster | Use hash tags `{tag}` for co-located keys |
| **Storing too much in session** | Large session objects per user | Store only userId in session, fetch rest from service |
| **No connection pool** | New connection per request | Configure Lettuce pool (`max-active`, `max-idle`) |
| **Ignoring serialization size** | Jackson serializes class metadata | Use compact serialization (e.g., Protobuf, custom) |
| **KEYS pattern in production** | O(N) scan blocks Redis | Use SCAN instead: `redisTemplate.scan(ScanOptions...)` |
| **Not handling Redis downtime** | App fails when Redis unavailable | Circuit breaker + graceful degradation to DB |

### TTL Jitter

```java
// Prevent thundering herd
public Duration ttlWithJitter(Duration base) {
    long jitter = (long)(base.toMillis() * 0.1 * Math.random());
    return base.plusMillis(jitter);
}

// Usage
redisTemplate.opsForValue().set(key, value, ttlWithJitter(Duration.ofMinutes(30)));
```

### SCAN Instead of KEYS

```java
// WRONG — blocks Redis
redisTemplate.keys("user:*").collectList().block();

// CORRECT — non-blocking iteration
redisTemplate.scan(ScanOptions.scanOptions().match("user:*").count(100).build())
    .flatMap(key -> redisTemplate.delete(key))
    .subscribe();
```
