# Redis Data Structures Reference

Hash, Sorted Set, HyperLogLog, Set membership, and serialization strategies.

## Table of Contents
- [Hash — Object Storage](#hash--object-storage)
- [Sorted Set — Leaderboard](#sorted-set--leaderboard)
- [HyperLogLog — Unique Counting](#hyperloglog--unique-counting)
- [Set — Membership & Relations](#set--membership--relations)
- [List — Queue / Stack](#list--queue--stack)
- [Serialization Strategies](#serialization-strategies)

---

## Hash — Object Storage

Use when you need to store an object's fields and access individual fields without full serialization.

```java
@Service @RequiredArgsConstructor
public class UserHashRepository {
    private final ReactiveRedisTemplate<String, String> redisTemplate;
    private final ObjectMapper objectMapper;

    private static final Duration TTL = Duration.ofHours(1);

    public Mono<Void> save(User user) {
        String key = "user:hash:" + user.id();
        Map<String, String> fields = Map.of(
            "id", user.id(),
            "email", user.email(),
            "name", user.name(),
            "status", user.status().name(),
            "createdAt", user.createdAt().toString()
        );
        return redisTemplate.opsForHash().putAll(key, fields)
            .then(redisTemplate.expire(key, TTL))
            .then();
    }

    public Mono<User> findById(String userId) {
        String key = "user:hash:" + userId;
        return redisTemplate.<String, String>opsForHash().entries(key)
            .collectMap(Map.Entry::getKey, Map.Entry::getValue)
            .filter(m -> !m.isEmpty())
            .map(fields -> new User(
                fields.get("id"),
                fields.get("email"),
                fields.get("name"),
                UserStatus.valueOf(fields.get("status")),
                Instant.parse(fields.get("createdAt"))
            ))
            .switchIfEmpty(Mono.error(new NotFoundException("User not found: " + userId)));
    }

    // Partial update — update only specific fields
    public Mono<Void> updateEmail(String userId, String newEmail) {
        return redisTemplate.opsForHash().put("user:hash:" + userId, "email", newEmail).then();
    }

    // Get specific field
    public Mono<String> getEmail(String userId) {
        return redisTemplate.<String, String>opsForHash()
            .get("user:hash:" + userId, "email");
    }

    // Atomic increment (e.g., counters stored in hash)
    public Mono<Long> incrementLoginCount(String userId) {
        return redisTemplate.opsForHash()
            .increment("user:hash:" + userId, "loginCount", 1L);
    }
}
```

---

## Sorted Set — Leaderboard

```java
@Service @RequiredArgsConstructor
public class LeaderboardService {
    private final ReactiveRedisTemplate<String, String> redisTemplate;
    private static final String LEADERBOARD_KEY = "leaderboard:global";

    // Update score
    public Mono<Double> updateScore(String userId, double score) {
        return redisTemplate.opsForZSet().add(LEADERBOARD_KEY, userId, score)
            .then(redisTemplate.opsForZSet().score(LEADERBOARD_KEY, userId));
    }

    // Increment score
    public Mono<Double> incrementScore(String userId, double delta) {
        return redisTemplate.opsForZSet().incrementScore(LEADERBOARD_KEY, userId, delta);
    }

    // Get top N (highest scores, DESC)
    public Flux<ZSetOperations.TypedTuple<String>> getTopN(int n) {
        return redisTemplate.opsForZSet()
            .reverseRangeWithScores(LEADERBOARD_KEY, Range.closed(0L, (long)(n - 1)));
    }

    // Get rank (0-indexed, lower = better rank)
    public Mono<Long> getRank(String userId) {
        return redisTemplate.opsForZSet().reverseRank(LEADERBOARD_KEY, userId);
    }

    // Get users in score range
    public Flux<String> getUsersInScoreRange(double min, double max) {
        return redisTemplate.opsForZSet()
            .rangeByScore(LEADERBOARD_KEY, Range.closed(min, max));
    }

    // Paginate leaderboard
    public Mono<List<LeaderboardEntry>> getPage(int page, int size) {
        long start = (long) page * size;
        long end = start + size - 1;
        return redisTemplate.opsForZSet()
            .reverseRangeWithScores(LEADERBOARD_KEY, Range.closed(start, end))
            .index()
            .map(indexed -> new LeaderboardEntry(
                (int)(start + indexed.getT1() + 1),  // rank
                indexed.getT2().getValue(),            // userId
                indexed.getT2().getScore()))           // score
            .collectList();
    }
}
```

---

## HyperLogLog — Unique Counting

Space-efficient approximate counting (~0.81% standard error). 12KB regardless of cardinality.

```java
@Service @RequiredArgsConstructor
public class UniqueCountService {
    private final ReactiveRedisTemplate<String, String> redisTemplate;

    // Track unique page views
    public Mono<Long> trackPageView(String pageId, String userId) {
        String key = "uv:page:" + pageId + ":" + LocalDate.now();
        return redisTemplate.opsForHyperLogLog().add(key, userId)
            .then(redisTemplate.expire(key, Duration.ofDays(30)))
            .then(redisTemplate.opsForHyperLogLog().size(key));
    }

    // Get unique count
    public Mono<Long> getUniqueVisitors(String pageId) {
        return redisTemplate.opsForHyperLogLog()
            .size("uv:page:" + pageId + ":" + LocalDate.now());
    }

    // Merge multiple HLLs (e.g., daily → weekly)
    public Mono<Long> getWeeklyUniques(String pageId) {
        String[] dailyKeys = IntStream.range(0, 7)
            .mapToObj(i -> "uv:page:" + pageId + ":" + LocalDate.now().minusDays(i))
            .toArray(String[]::new);
        String weeklyKey = "uv:page:weekly:" + pageId;
        return redisTemplate.opsForHyperLogLog().union(weeklyKey, dailyKeys)
            .then(redisTemplate.opsForHyperLogLog().size(weeklyKey));
    }
}
```

---

## Set — Membership & Relations

```java
@Service @RequiredArgsConstructor
public class SetService {
    private final ReactiveRedisTemplate<String, String> redisTemplate;

    // User interests tracking
    public Mono<Long> addInterest(String userId, String category) {
        return redisTemplate.opsForSet().add("user:interests:" + userId, category);
    }

    public Mono<Boolean> hasInterest(String userId, String category) {
        return redisTemplate.opsForSet().isMember("user:interests:" + userId, category);
    }

    public Flux<String> getInterests(String userId) {
        return redisTemplate.opsForSet().members("user:interests:" + userId);
    }

    // Set operations
    public Flux<String> commonInterests(String userId1, String userId2) {
        return redisTemplate.opsForSet().intersect(
            "user:interests:" + userId1,
            "user:interests:" + userId2);
    }

    public Flux<String> allInterests(String userId1, String userId2) {
        return redisTemplate.opsForSet().union(
            "user:interests:" + userId1,
            "user:interests:" + userId2);
    }

    // Bloom filter alternative — check if item was seen before
    public Mono<Boolean> hasBeenSeen(String feedId, String itemId) {
        return redisTemplate.opsForSet().isMember("seen:" + feedId, itemId);
    }

    public Mono<Long> markAsSeen(String feedId, String itemId) {
        return redisTemplate.opsForSet().add("seen:" + feedId, itemId);
    }
}
```

---

## List — Queue / Stack

```java
@Service @RequiredArgsConstructor
public class ListService {
    private final ReactiveRedisTemplate<String, String> redisTemplate;

    // Queue (FIFO) — lpush + rpop
    public Mono<Long> enqueue(String queueName, String item) {
        return redisTemplate.opsForList().leftPush(queueName, item);
    }

    public Mono<String> dequeue(String queueName) {
        return redisTemplate.opsForList().rightPop(queueName);
    }

    // Stack (LIFO) — lpush + lpop
    public Mono<Long> push(String stackName, String item) {
        return redisTemplate.opsForList().leftPush(stackName, item);
    }

    public Mono<String> pop(String stackName) {
        return redisTemplate.opsForList().leftPop(stackName);
    }

    // Blocking pop with timeout (for job queues)
    public Mono<String> blockingDequeue(String queueName, Duration timeout) {
        return redisTemplate.opsForList().rightPop(queueName, timeout);
    }

    // Recent activity log (capped list)
    public Mono<Void> addActivity(String userId, String activity, int maxSize) {
        String key = "activity:" + userId;
        return redisTemplate.opsForList().leftPush(key, activity)
            .then(redisTemplate.opsForList().trim(key, 0, maxSize - 1))
            .then();
    }

    public Flux<String> getRecentActivity(String userId) {
        return redisTemplate.opsForList().range("activity:" + userId, 0, -1);
    }
}
```

---

## Serialization Strategies

### Jackson JSON (default, human-readable)

```java
@Bean
public ReactiveRedisTemplate<String, Object> reactiveRedisTemplate(
        ReactiveRedisConnectionFactory factory) {
    Jackson2JsonRedisSerializer<Object> serializer =
        new Jackson2JsonRedisSerializer<>(Object.class);
    RedisSerializationContext<String, Object> context = RedisSerializationContext
        .<String, Object>newSerializationContext(new StringRedisSerializer())
        .value(serializer)
        .hashValue(serializer)
        .build();
    return new ReactiveRedisTemplate<>(factory, context);
}
```

### Type-Safe with Class Information

```java
// Embeds @class field — enables polymorphic deserialization
GenericJackson2JsonRedisSerializer serializer = new GenericJackson2JsonRedisSerializer();
```

### Serialization Comparison

| Strategy | Size | Speed | Type Safety | Human Readable | Best For |
|---|---|---|---|---|---|
| Jackson JSON | Medium | Medium | Yes (with type hints) | Yes | General use |
| GenericJackson2Json | Larger | Medium | Yes (polymorphic) | Yes | Heterogeneous objects |
| Kryo | Small | Fast | No (fragile) | No | High-volume, fixed schema |
| Protobuf | Smallest | Fastest | Yes | No | Cross-language, production |
| String | Varies | Fastest | Manual | Yes | Simple values |

### Protobuf Serializer

```java
public class ProtobufRedisSerializer<T extends GeneratedMessageV3>
        implements RedisSerializer<T> {
    private final Parser<T> parser;

    @Override
    public byte[] serialize(T t) throws SerializationException {
        return t == null ? null : t.toByteArray();
    }

    @Override
    public T deserialize(byte[] bytes) throws SerializationException {
        try {
            return bytes == null ? null : parser.parseFrom(bytes);
        } catch (InvalidProtocolBufferException e) {
            throw new SerializationException("Protobuf deserialization failed", e);
        }
    }
}
```
