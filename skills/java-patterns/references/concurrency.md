# Concurrency Patterns

## Table of Contents

- [CompletableFuture](#completablefuture)
- [Virtual Threads (Java 21+)](#virtual-threads-java-21)
- [Thread Safety](#thread-safety)
- [Concurrent Collections](#concurrent-collections)
- [Executor Patterns](#executor-patterns)

---

## CompletableFuture

### Basic Patterns

```java
// Async operation
CompletableFuture<User> userFuture = CompletableFuture.supplyAsync(
    () -> userRepository.findById(id),
    executor
);

// Chaining
CompletableFuture<OrderSummary> summary = userFuture
    .thenCompose(user -> orderService.getOrdersFor(user.id()))
    .thenApply(orders -> new OrderSummary(orders));

// Combining multiple futures
CompletableFuture<Void> allDone = CompletableFuture.allOf(
    future1, future2, future3
);

// Any of multiple futures
CompletableFuture<Object> anyDone = CompletableFuture.anyOf(
    future1, future2, future3
);
```

### Error Handling

```java
CompletableFuture<User> result = fetchUser(id)
    .exceptionally(ex -> {
        log.error("Failed to fetch user", ex);
        return User.UNKNOWN;  // fallback
    });

// With recovery
CompletableFuture<User> result = fetchUser(id)
    .exceptionallyCompose(ex -> {
        log.warn("Primary failed, trying backup", ex);
        return fetchUserFromBackup(id);
    });

// Handle both success and failure
future.handle((result, ex) -> {
    if (ex != null) {
        return handleError(ex);
    }
    return processResult(result);
});
```

### Timeout

```java
// Java 9+
CompletableFuture<User> result = fetchUser(id)
    .orTimeout(5, TimeUnit.SECONDS)
    .exceptionally(ex -> {
        if (ex.getCause() instanceof TimeoutException) {
            return User.UNKNOWN;
        }
        throw new CompletionException(ex);
    });

// With default on timeout
CompletableFuture<User> result = fetchUser(id)
    .completeOnTimeout(User.UNKNOWN, 5, TimeUnit.SECONDS);
```

## Virtual Threads (Java 21+)

### Basic Usage

```java
// Create virtual thread
Thread.startVirtualThread(() -> {
    processRequest(request);
});

// Virtual thread executor
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    List<Future<Result>> futures = requests.stream()
        .map(req -> executor.submit(() -> process(req)))
        .toList();
}

// Structured concurrency (Java 21+ preview)
try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
    Future<User> userFuture = scope.fork(() -> fetchUser(id));
    Future<List<Order>> ordersFuture = scope.fork(() -> fetchOrders(id));
    
    scope.join();
    scope.throwIfFailed();
    
    return new UserWithOrders(userFuture.resultNow(), ordersFuture.resultNow());
}
```

### When to Use Virtual Threads

```
✅ Use for:
- I/O-bound operations (HTTP calls, DB queries)
- Many concurrent tasks that mostly wait
- Replacing thread pools for blocking code

❌ Avoid for:
- CPU-bound computations (use ForkJoinPool)
- When you need thread-local caching
- Synchronized blocks with long-held locks
```

## Thread Safety

### Immutable Objects (Preferred)

```java
// Immutable = thread-safe by default
public record UserContext(String userId, Set<String> roles) {
    public UserContext {
        roles = Set.copyOf(roles);  // Defensive copy
    }
}
```

### Atomic Variables

```java
public class Counter {
    private final AtomicLong count = new AtomicLong();
    
    public long increment() {
        return count.incrementAndGet();
    }
    
    // Compare and swap
    public boolean tryUpdate(long expected, long newValue) {
        return count.compareAndSet(expected, newValue);
    }
}

// AtomicReference for objects
private final AtomicReference<Config> config = new AtomicReference<>(Config.DEFAULT);

public void updateConfig(Config newConfig) {
    config.set(newConfig);
}
```

### Locks

```java
public class UserCache {
    private final Map<String, User> cache = new HashMap<>();
    private final ReadWriteLock lock = new ReentrantReadWriteLock();
    
    public User get(String id) {
        lock.readLock().lock();
        try {
            return cache.get(id);
        } finally {
            lock.readLock().unlock();
        }
    }
    
    public void put(String id, User user) {
        lock.writeLock().lock();
        try {
            cache.put(id, user);
        } finally {
            lock.writeLock().unlock();
        }
    }
}
```

## Concurrent Collections

### Thread-Safe Maps

```java
// ConcurrentHashMap - best general purpose
ConcurrentHashMap<String, User> cache = new ConcurrentHashMap<>();

// Atomic operations
cache.computeIfAbsent(id, k -> loadUser(k));
cache.compute(id, (k, v) -> v == null ? loadUser(k) : refreshUser(v));
cache.merge(id, 1, Integer::sum);  // Counting

// Bulk operations with parallelism
cache.forEach(4, (k, v) -> process(v));
long count = cache.reduceValues(4, v -> v.isActive() ? 1L : 0L, Long::sum);
```

### Thread-Safe Queues

```java
// Bounded blocking queue
BlockingQueue<Task> queue = new ArrayBlockingQueue<>(100);

// Producer
queue.put(task);  // Blocks if full

// Consumer
Task task = queue.take();  // Blocks if empty

// Non-blocking with timeout
Task task = queue.poll(1, TimeUnit.SECONDS);
```

## Executor Patterns

### Configuring Thread Pools

```java
// Fixed thread pool for CPU-bound tasks
ExecutorService cpuPool = Executors.newFixedThreadPool(
    Runtime.getRuntime().availableProcessors()
);

// Cached pool for I/O-bound tasks (be careful with unbounded)
ExecutorService ioPool = Executors.newCachedThreadPool();

// Custom configuration
ThreadPoolExecutor executor = new ThreadPoolExecutor(
    10,                        // core pool size
    50,                       // max pool size
    60, TimeUnit.SECONDS,     // keep-alive
    new LinkedBlockingQueue<>(1000),  // bounded queue
    new ThreadPoolExecutor.CallerRunsPolicy()  // rejection policy
);

// Scheduled tasks
ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(2);
scheduler.scheduleAtFixedRate(
    () -> refreshCache(),
    0, 5, TimeUnit.MINUTES
);
```

### Graceful Shutdown

```java
public void shutdown() {
    executor.shutdown();
    try {
        if (!executor.awaitTermination(30, TimeUnit.SECONDS)) {
            executor.shutdownNow();
            if (!executor.awaitTermination(30, TimeUnit.SECONDS)) {
                log.error("Executor did not terminate");
            }
        }
    } catch (InterruptedException e) {
        executor.shutdownNow();
        Thread.currentThread().interrupt();
    }
}
```
