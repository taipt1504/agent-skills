# Java Patterns Reference

Immutability, null safety, concurrency, collections, streams, and memory optimization.

## Table of Contents
- [Immutability](#immutability)
- [Null Safety](#null-safety)
- [Concurrency](#concurrency)
- [Collections](#collections)
- [Streams & Functional](#streams--functional)
- [Memory Optimization & GC](#memory-optimization--gc)

---

## Immutability

### Records (Java 14+)

```java
// Simple record with validation
public record UserId(String value) {
    public UserId { Objects.requireNonNull(value); if (value.isBlank()) throw new IllegalArgumentException(); }
    public static UserId generate() { return new UserId(UUID.randomUUID().toString()); }
}

// Record with validation and behavior
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount);
        Objects.requireNonNull(currency);
        if (amount.scale() > currency.getDefaultFractionDigits())
            throw new IllegalArgumentException("Invalid scale");
    }
    public Money add(Money other) {
        if (!currency.equals(other.currency)) throw new IllegalArgumentException("Currency mismatch");
        return new Money(amount.add(other.amount), currency);
    }
}

// Record with @Builder (Lombok)
@Builder
public record CreateUserCommand(
    @NonNull String name,
    @NonNull String email,
    @Builder.Default Instant createdAt = Instant.now(),
    @Builder.Default Set<String> roles = Set.of()
) {}
```

### Lombok @Value

For classes needing inheritance or complex logic:

```java
@Value @Builder
public class UserProfile {
    @NonNull String id;
    @NonNull String name;
    String bio;
    @Builder.Default List<String> interests = List.of();
    @Builder.Default Instant createdAt = Instant.now();
}
```

### Builder — Copy with Modification

```java
@Builder(toBuilder = true)
public record Order(String id, String customerId, List<OrderItem> items, OrderStatus status) {
    public Order withStatus(OrderStatus newStatus) {
        return this.toBuilder().status(newStatus).build();
    }
}
Order updated = order.toBuilder().status(OrderStatus.COMPLETED).build();
```

### Defensive Copies

```java
public record Order(String id, List<OrderItem> items) {
    public Order { items = List.copyOf(items); }  // immutable copy on input
}

public List<Order> getOrders() {
    return List.copyOf(orders);  // defensive copy on return
}
```

### Immutable Collections

```java
List<String> list = List.of("a", "b", "c");              // factory
List<String> copy = List.copyOf(mutableList);             // from mutable
List<String> collected = stream.collect(Collectors.toUnmodifiableList()); // from stream
List<String> modern = stream.toList();                     // Java 16+
```

| Type | Use Case |
|------|----------|
| `List.of()` | Small, known at compile time |
| `List.copyOf()` | Converting existing collection |
| `Collections.unmodifiableList()` | Wrapper (original still mutable) |
| `Collectors.toUnmodifiableList()` | Stream terminal operation |

---

## Null Safety

### Optional Patterns

```java
// Return Optional from methods
public Optional<User> findById(String id) { return Optional.ofNullable(cache.get(id)); }

// Chaining
User user = findById(id).orElseThrow(() -> new UserNotFoundException(id));
User user = findById(id).orElseGet(() -> createDefaultUser());

// Filter
Optional<User> active = findById(id).filter(User::isActive);

// Convert to Stream
List<User> users = userIds.stream()
    .map(this::findById)
    .flatMap(Optional::stream)
    .toList();

// NEVER: Optional as field, parameter, or collection element
// NEVER: .get() without isPresent check
```

### Null Validation

```java
// Constructor
this.repository = Objects.requireNonNull(repository, "repository must not be null");

// Record compact constructor
public record PageRequest(int page, int size) {
    public PageRequest {
        if (page < 0) throw new IllegalArgumentException("page must be >= 0");
        if (size < 1 || size > 100) throw new IllegalArgumentException("size must be 1-100");
    }
}

// Bean Validation
public record CreateUserRequest(
    @NotBlank String name,
    @NotNull @Email String email,
    @Size(min = 8, max = 100) String password
) {}
```

### Null Object Pattern

```java
NotificationSender sender = config.enabled()
    ? new EmailNotificationSender()
    : NoOpNotificationSender.INSTANCE;
sender.send(notification);  // always safe
```

---

## Concurrency

### CompletableFuture

```java
// Async + chaining
CompletableFuture<OrderSummary> summary = CompletableFuture
    .supplyAsync(() -> userRepository.findById(id), executor)
    .thenCompose(user -> orderService.getOrdersFor(user.id()))
    .thenApply(OrderSummary::new);

// Combining
CompletableFuture.allOf(future1, future2, future3);

// Error handling
result.exceptionally(ex -> { log.error("Failed", ex); return fallback; });
result.exceptionallyCompose(ex -> fetchFromBackup(id));

// Timeout (Java 9+)
result.orTimeout(5, TimeUnit.SECONDS);
result.completeOnTimeout(defaultValue, 5, TimeUnit.SECONDS);
```

### Virtual Threads (Java 21+)

```java
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    List<Future<Result>> futures = requests.stream()
        .map(req -> executor.submit(() -> process(req)))
        .toList();
}

// Structured concurrency (preview)
try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
    Future<User> userFuture = scope.fork(() -> fetchUser(id));
    Future<List<Order>> ordersFuture = scope.fork(() -> fetchOrders(id));
    scope.join(); scope.throwIfFailed();
    return new UserWithOrders(userFuture.resultNow(), ordersFuture.resultNow());
}
```

Use virtual threads for I/O-bound ops. Avoid for CPU-bound, thread-local caching, long-held synchronized blocks.

### Atomic Variables

```java
private final AtomicLong count = new AtomicLong();
count.incrementAndGet();
count.compareAndSet(expected, newValue);

private final AtomicReference<Config> config = new AtomicReference<>(Config.DEFAULT);
```

### Thread-Safe Collections

```java
ConcurrentHashMap<String, User> cache = new ConcurrentHashMap<>();
cache.computeIfAbsent(id, k -> loadUser(k));  // atomic
cache.merge(id, 1, Integer::sum);              // counting

BlockingQueue<Task> queue = new ArrayBlockingQueue<>(100);
```

### Executor Configuration

```java
// CPU-bound
ExecutorService cpuPool = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors());

// Custom with rejection policy
new ThreadPoolExecutor(10, 50, 60, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(1000), new ThreadPoolExecutor.CallerRunsPolicy());
```

---

## Collections

### Choosing the Right Collection

**Lists**: `ArrayList` (random access), `LinkedList` (queue ops), `CopyOnWriteArrayList` (few writes, many reads).
**Sets**: `HashSet` (fast lookup), `LinkedHashSet` (insertion order), `TreeSet` (sorted), `EnumSet` (enum values).
**Maps**: `HashMap` (fast), `LinkedHashMap` (order), `TreeMap` (sorted), `EnumMap` (enum keys), `ConcurrentHashMap` (thread-safe).

### Pre-sizing

```java
List<User> users = new ArrayList<>(expectedSize);
int initialCapacity = (int) (expectedSize / 0.75) + 1;
Map<String, User> map = new HashMap<>(initialCapacity);
```

### Map Operations

```java
cache.computeIfAbsent(key, k -> expensiveComputation(k));  // atomic get-or-create
counts.merge(word, 1, Integer::sum);                         // counting
int count = counts.getOrDefault(key, 0);                     // safe access
```

### Avoid Pitfalls

```java
users.removeIf(User::isInactive);  // not manual for-loop remove
map.forEach((k, v) -> process(k, v));  // not keySet() + get()
```

### Grouping & Partitioning

```java
Map<Status, List<Order>> byStatus = orders.stream()
    .collect(Collectors.groupingBy(Order::status));
Map<Status, Long> countByStatus = orders.stream()
    .collect(Collectors.groupingBy(Order::status, Collectors.counting()));
Map<Boolean, List<User>> partition = users.stream()
    .collect(Collectors.partitioningBy(User::isActive));
```

---

## Streams & Functional

### Best Practices

```java
// Filter early
users.stream().filter(User::isActive).map(this::expensiveTransform).toList();

// Primitive streams (avoid boxing)
int sum = orders.stream().mapToInt(Order::quantity).sum();

// Short-circuit
boolean hasAdmin = users.stream().anyMatch(User::isAdmin);

// flatMap for one-to-many
List<Order> all = users.stream().flatMap(u -> u.orders().stream()).toList();
```

### When NOT to Use Streams

```java
users.forEach(this::process);  // simpler than stream().forEach()
!users.isEmpty();               // simpler than stream().findAny().isPresent()
```

### Parallel Streams

Use when: >10K elements, CPU-intensive, independent ops, order doesn't matter.
Avoid when: small data, I/O-bound, side effects, inside reactive code.

---

## Memory Optimization & GC

### Avoid Unnecessary Object Creation

```java
// Use primitives over wrappers
int value = 1000;  // not Integer.valueOf(1000)

// StringBuilder in loops
StringBuilder sb = new StringBuilder(expectedLength);
for (String s : strings) sb.append(s);

// String.join for simple cases
String result = String.join(", ", strings);
```

### Caching Patterns

```java
// Caffeine (recommended)
LoadingCache<String, User> cache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(Duration.ofMinutes(10))
    .refreshAfterWrite(Duration.ofMinutes(5))
    .build(key -> userRepository.findById(key));
```

### Memory Leak Prevention

- Close resources with try-with-resources.
- Use static inner classes or lambdas (not anonymous inner classes holding outer reference).
- Use WeakReference for listener registrations.
- Never let static collections grow unbounded.

### GC Tuning

```bash
-XX:+UseG1GC                   # Default Java 9+ (good general purpose)
-XX:+UseZGC                    # Java 15+ (ultra-low latency <1ms)
-Xms4g -Xmx4g                 # Set min=max (avoid resize pauses)
-Xlog:gc*:file=gc.log:time    # GC logging
```
