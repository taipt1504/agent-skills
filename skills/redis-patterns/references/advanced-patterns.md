# Redis Advanced Patterns Reference

Rate limiting (full Lua), Pub/Sub + SSE, Redis Streams, distributed locking details.

## Table of Contents
- [Rate Limiting — Full Lua Script](#rate-limiting--full-lua-script)
- [WebFlux Rate Limiter Filter](#webflux-rate-limiter-filter)
- [Pub/Sub Patterns](#pubsub-patterns)
- [SSE with Redis Pub/Sub](#sse-with-redis-pubsub)
- [Redis Streams — Producer](#redis-streams--producer)
- [Redis Streams — Consumer Group](#redis-streams--consumer-group)
- [Stream Trimming](#stream-trimming)
- [RedisTemplate-Based Lock (Simple)](#redistemplate-based-lock-simple)
- [Redisson Advanced Lock Options](#redisson-advanced-lock-options)

---

## Rate Limiting — Full Lua Script

```java
@Service @RequiredArgsConstructor
public class RedisRateLimiter {
    private final ReactiveRedisTemplate<String, Object> redisTemplate;

    public Mono<RateLimitResult> isAllowed(String clientId, int maxRequests, Duration window) {
        String key = "ratelimit:" + clientId;
        long now = Instant.now().toEpochMilli();
        long windowStart = now - window.toMillis();

        String luaScript = """
            redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, ARGV[1])
            local count = redis.call('ZCARD', KEYS[1])
            if count < tonumber(ARGV[2]) then
                redis.call('ZADD', KEYS[1], ARGV[3], ARGV[3] .. ':' .. math.random(1000000))
                redis.call('PEXPIRE', KEYS[1], ARGV[4])
                return {1, tonumber(ARGV[2]) - count - 1}
            else
                return {0, 0}
            end
            """;

        return redisTemplate.execute(
            RedisScript.of(luaScript, List.class),
            List.of(key),
            List.of(String.valueOf(windowStart), String.valueOf(maxRequests),
                    String.valueOf(now), String.valueOf(window.toMillis()))
        ).next().map(result -> {
            List<Long> res = (List<Long>) result;
            return new RateLimitResult(res.get(0) == 1, res.get(1).intValue());
        });
    }
}

public record RateLimitResult(boolean allowed, int remaining) {}
```

## WebFlux Rate Limiter Filter

```java
@Component @RequiredArgsConstructor
public class RateLimitWebFilter implements WebFilter {
    private final RedisRateLimiter rateLimiter;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String clientIp = Objects.requireNonNull(exchange.getRequest().getRemoteAddress())
            .getAddress().getHostAddress();
        return rateLimiter.isAllowed(clientIp, 100, Duration.ofMinutes(1))
            .flatMap(result -> {
                exchange.getResponse().getHeaders().add("X-RateLimit-Remaining",
                    String.valueOf(result.remaining()));
                if (!result.allowed()) {
                    exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                    exchange.getResponse().getHeaders().add("Retry-After", "60");
                    return exchange.getResponse().setComplete();
                }
                return chain.filter(exchange);
            });
    }
}
```

## Pub/Sub Patterns

### Configuration

```java
@Configuration
public class RedisPubSubConfig {
    @Bean
    public ReactiveRedisMessageListenerContainer messageListenerContainer(
            ReactiveRedisConnectionFactory factory) {
        return new ReactiveRedisMessageListenerContainer(factory);
    }
}
```

### Publisher

```java
@Service @RequiredArgsConstructor
public class RedisEventPublisher {
    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;

    public Mono<Long> publish(String channel, Object event) {
        try {
            return redisTemplate.convertAndSend(channel, objectMapper.writeValueAsString(event));
        } catch (JsonProcessingException e) {
            return Mono.error(e);
        }
    }

    public Mono<Long> publishOrderUpdate(OrderStatusEvent event) {
        return publish("order:status:" + event.orderId(), event);
    }
}
```

### Subscriber

```java
@Service @RequiredArgsConstructor
public class RedisEventSubscriber {
    private final ReactiveRedisMessageListenerContainer container;
    private final ObjectMapper objectMapper;

    public Flux<OrderStatusEvent> subscribeToOrderUpdates(String orderId) {
        return container.receive(ChannelTopic.of("order:status:" + orderId))
            .map(message -> {
                try {
                    return objectMapper.readValue(
                        message.getMessage().toString(), OrderStatusEvent.class);
                } catch (JsonProcessingException e) {
                    throw new RuntimeException("Deserialization failed", e);
                }
            });
    }

    // Pattern subscription — wildcard matching
    public Flux<Message<String, String>> subscribeToPattern(String pattern) {
        return container.receive(PatternTopic.of(pattern)).map(m -> m);
    }
}
```

## SSE with Redis Pub/Sub

```java
@RestController @RequiredArgsConstructor
public class OrderStatusController {
    private final RedisEventSubscriber subscriber;

    @GetMapping(value = "/api/orders/{orderId}/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<OrderStatusEvent>> streamOrderStatus(@PathVariable String orderId) {
        return subscriber.subscribeToOrderUpdates(orderId)
            .map(event -> ServerSentEvent.<OrderStatusEvent>builder()
                .id(UUID.randomUUID().toString())
                .event("order-status")
                .data(event)
                .build());
    }
}
```

## Redis Streams — Producer

```java
@Service @RequiredArgsConstructor
public class RedisStreamProducer {
    private final ReactiveRedisTemplate<String, Object> redisTemplate;

    public Mono<RecordId> publishOrderEvent(OrderEvent event) {
        Map<String, String> fields = Map.of(
            "orderId", event.orderId(),
            "status", event.status().name(),
            "amount", event.amount().toString(),
            "timestamp", Instant.now().toString()
        );
        return redisTemplate.opsForStream()
            .add(StreamRecords.newRecord().ofMap(fields).withStreamKey("stream:orders"));
    }
}
```

## Redis Streams — Consumer Group

```java
@Service @RequiredArgsConstructor
public class RedisStreamConsumer {
    private final ReactiveRedisTemplate<String, Object> redisTemplate;
    private static final String STREAM_KEY = "stream:orders";
    private static final String GROUP = "order-processors";
    private static final String CONSUMER = "consumer-" + UUID.randomUUID().toString().substring(0, 8);

    @PostConstruct
    public void init() {
        // Create consumer group if not exists
        redisTemplate.opsForStream()
            .createGroup(STREAM_KEY, ReadOffset.from("0"), GROUP)
            .onErrorResume(e -> e.getMessage() != null && e.getMessage().contains("BUSYGROUP")
                ? Mono.just("OK") : Mono.error(e))
            .then(startConsuming())
            .subscribe();
    }

    private Mono<Void> startConsuming() {
        return redisTemplate.opsForStream()
            .read(Consumer.from(GROUP, CONSUMER),
                StreamReadOptions.empty().count(10).block(Duration.ofSeconds(5)),
                StreamOffset.create(STREAM_KEY, ReadOffset.lastConsumed()))
            .flatMap(this::processAndAck)
            .repeat()
            .then();
    }

    private Mono<Void> processAndAck(MapRecord<String, Object, Object> record) {
        return processOrder(record.getValue())
            .then(redisTemplate.opsForStream().acknowledge(STREAM_KEY, GROUP, record.getId()))
            .then();
    }
}
```

## Stream Trimming

```java
// Keep only last 10,000 messages
redisTemplate.opsForStream().trim(STREAM_KEY, 10_000);

// Approximate trimming (more efficient — MAXLEN ~)
redisTemplate.opsForStream().trim(STREAM_KEY, 10_000, true);
```

## RedisTemplate-Based Lock (Simple)

```java
// Acquire: SET NX EX (atomic)
public Mono<Boolean> tryLock(String lockKey, String lockValue, Duration ttl) {
    return redisTemplate.opsForValue().setIfAbsent(lockKey, lockValue, ttl);
}

// Release: Lua script for atomicity (check-and-delete)
public Mono<Boolean> unlock(String lockKey, String lockValue) {
    String luaScript = """
        if redis.call('get', KEYS[1]) == ARGV[1] then
            return redis.call('del', KEYS[1])
        else
            return 0
        end
        """;
    return redisTemplate.execute(
        RedisScript.of(luaScript, Long.class),
        List.of(lockKey), List.of(lockValue)
    ).next().map(result -> result > 0);
}
```

## Redisson Advanced Lock Options

```java
// Fair lock — FIFO ordering, no thread starvation
public <T> Mono<T> executeWithFairLock(String resourceId, Mono<T> task) {
    RLockReactive lock = redissonClient.reactive().getFairLock("fair-lock:" + resourceId);
    return lock.lock(30, TimeUnit.SECONDS)
        .then(task)
        .doFinally(signal -> lock.unlock().subscribe());
}

// ReadWriteLock — multiple readers, one writer
public <T> Mono<T> readWithLock(String resourceId, Mono<T> readTask) {
    RReadWriteLockReactive rwLock = redissonClient.reactive().getReadWriteLock("rwlock:" + resourceId);
    return rwLock.readLock().lock(10, TimeUnit.SECONDS)
        .then(readTask)
        .doFinally(signal -> rwLock.readLock().unlock().subscribe());
}
```
