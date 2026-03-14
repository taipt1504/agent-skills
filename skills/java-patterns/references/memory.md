# Memory Optimization Patterns

## Table of Contents

- [Object Creation](#object-creation)
- [String Optimization](#string-optimization)
- [Collection Sizing](#collection-sizing)
- [Caching Patterns](#caching-patterns)
- [Memory Leaks](#memory-leaks)
- [GC Tuning Tips](#gc-tuning-tips)

---

## Object Creation

### Avoid Unnecessary Object Creation

```java
// ❌ Creates new Boolean each time
Boolean.valueOf(someCondition)

// ✅ Reuse constants
Boolean.TRUE / Boolean.FALSE

// ❌ Creates new Integer each time for values outside -128 to 127
Integer.valueOf(1000)

// ✅ Use primitives when possible
int value = 1000;

// ❌ String concatenation in loop
String result = "";
for (String s : strings) {
    result += s;  // Creates new String each iteration
}

// ✅ StringBuilder
StringBuilder sb = new StringBuilder();
for (String s : strings) {
    sb.append(s);
}
String result = sb.toString();
```

### Object Pooling (for expensive objects)

```java
public class ConnectionPool {
    private final BlockingQueue<Connection> pool;
    
    public ConnectionPool(int size, Supplier<Connection> factory) {
        this.pool = new ArrayBlockingQueue<>(size);
        for (int i = 0; i < size; i++) {
            pool.offer(factory.get());
        }
    }
    
    public Connection acquire() throws InterruptedException {
        return pool.take();
    }
    
    public void release(Connection conn) {
        pool.offer(conn);
    }
    
    // Try-with-resources pattern
    public <T> T withConnection(Function<Connection, T> action) 
            throws InterruptedException {
        Connection conn = acquire();
        try {
            return action.apply(conn);
        } finally {
            release(conn);
        }
    }
}
```

### Flyweight Pattern

```java
// Cache and reuse immutable objects
public class Color {
    private static final Map<String, Color> CACHE = new ConcurrentHashMap<>();
    
    private final int r, g, b;
    
    private Color(int r, int g, int b) {
        this.r = r; this.g = g; this.b = b;
    }
    
    public static Color of(int r, int g, int b) {
        String key = r + "," + g + "," + b;
        return CACHE.computeIfAbsent(key, k -> new Color(r, g, b));
    }
    
    // Predefined constants
    public static final Color RED = of(255, 0, 0);
    public static final Color GREEN = of(0, 255, 0);
    public static final Color BLUE = of(0, 0, 255);
}
```

## String Optimization

### String Interning

```java
// ✅ Intern frequently compared strings
String status = inputStatus.intern();

// Then use == for comparison (faster than equals)
if (status == "ACTIVE") { ... }

// Note: Be careful with intern() - it uses PermGen/Metaspace
// Only use for small, finite set of strings
```

### Efficient String Operations

```java
// ✅ Pre-sized StringBuilder
StringBuilder sb = new StringBuilder(expectedLength);

// ✅ Use String.join for simple concatenation
String result = String.join(", ", strings);

// ✅ StringJoiner for more control
StringJoiner joiner = new StringJoiner(", ", "[", "]");
for (String s : strings) {
    joiner.add(s);
}

// ✅ Text blocks (Java 15+) - no runtime concatenation
String json = """
    {
        "name": "%s",
        "value": %d
    }
    """.formatted(name, value);
```

## Collection Sizing

### Initial Capacity

```java
// ✅ Size collections appropriately
List<User> users = new ArrayList<>(expectedCount);
Map<String, User> userMap = new HashMap<>(initialCapacity(expectedCount));
Set<String> ids = new HashSet<>(initialCapacity(expectedCount));

// Helper for HashMap capacity (accounts for load factor)
private static int initialCapacity(int expectedSize) {
    return (int) (expectedSize / 0.75) + 1;
}
```

### Trim Excess Capacity

```java
// After populating, trim excess
ArrayList<User> users = new ArrayList<>(1000);
// ... populate with only 100 entries
users.trimToSize();  // Releases unused capacity
```

## Caching Patterns

### Weak References (for memory-sensitive caches)

```java
public class WeakCache<K, V> {
    private final Map<K, WeakReference<V>> cache = new ConcurrentHashMap<>();
    
    public V get(K key) {
        WeakReference<V> ref = cache.get(key);
        return ref != null ? ref.get() : null;
    }
    
    public void put(K key, V value) {
        cache.put(key, new WeakReference<>(value));
    }
}

// Or use WeakHashMap for key-based weak references
Map<Key, Value> cache = Collections.synchronizedMap(new WeakHashMap<>());
```

### Soft References (for memory caches)

```java
// Soft references are cleared only when memory is low
public class SoftCache<K, V> {
    private final Map<K, SoftReference<V>> cache = new ConcurrentHashMap<>();
    private final ReferenceQueue<V> queue = new ReferenceQueue<>();
    
    public V get(K key) {
        cleanup();
        SoftReference<V> ref = cache.get(key);
        return ref != null ? ref.get() : null;
    }
    
    public void put(K key, V value) {
        cleanup();
        cache.put(key, new SoftReference<>(value, queue));
    }
    
    private void cleanup() {
        Reference<? extends V> ref;
        while ((ref = queue.poll()) != null) {
            // Remove stale entries
            cache.values().remove(ref);
        }
    }
}
```

### Caffeine Cache (recommended)

```java
// High-performance caching library
Cache<String, User> cache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(Duration.ofMinutes(10))
    .recordStats()  // For monitoring
    .build();

// Loading cache (auto-loads on miss)
LoadingCache<String, User> loadingCache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(Duration.ofMinutes(10))
    .refreshAfterWrite(Duration.ofMinutes(5))
    .build(key -> userRepository.findById(key));
```

## Memory Leaks

### Common Causes & Fixes

```java
// ❌ LEAK: Static collections that grow indefinitely
private static final List<EventListener> listeners = new ArrayList<>();

// ✅ FIX: Use WeakReference or explicit removal
private static final List<WeakReference<EventListener>> listeners = 
    new CopyOnWriteArrayList<>();

// ❌ LEAK: Forgetting to close resources
Connection conn = dataSource.getConnection();
// ... use connection but never close

// ✅ FIX: Try-with-resources
try (Connection conn = dataSource.getConnection()) {
    // use connection
}

// ❌ LEAK: Inner class holding reference to outer class
public class Outer {
    private byte[] largeData = new byte[1_000_000];
    
    public Runnable createTask() {
        return new Runnable() {
            public void run() {
                // This inner class holds reference to Outer.this
                // which keeps largeData alive!
            }
        };
    }
}

// ✅ FIX: Use static inner class or lambda
public Runnable createTask() {
    return () -> {
        // Lambda only captures what it uses
    };
}
```

## GC Tuning Tips

### Choosing GC

```bash
# G1GC (default Java 9+) - good general purpose
-XX:+UseG1GC

# ZGC (Java 15+) - ultra-low latency (<1ms pauses)
-XX:+UseZGC

# Shenandoah (Java 12+) - low latency
-XX:+UseShenandoahGC
```

### Heap Sizing

```bash
# Set min and max to same value (avoid resize pauses)
-Xms4g -Xmx4g

# New generation sizing (for high-allocation apps)
-XX:NewRatio=2  # Old:New = 2:1
```

### GC Logging

```bash
# Java 9+ unified logging
-Xlog:gc*:file=gc.log:time,uptime,level,tags:filecount=5,filesize=100m
```

### Monitoring

```java
// Get memory info programmatically
MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();
MemoryUsage heapUsage = memoryBean.getHeapMemoryUsage();

long used = heapUsage.getUsed();
long max = heapUsage.getMax();
double percentUsed = (double) used / max * 100;

log.info("Heap usage: {}% ({}/{} MB)", 
    String.format("%.1f", percentUsed),
    used / 1_000_000,
    max / 1_000_000);
```
