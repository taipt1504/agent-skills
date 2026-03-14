# Collections Patterns

## Table of Contents

- [Choosing the Right Collection](#choosing-the-right-collection)
- [Initialization Best Practices](#initialization-best-practices)
- [Performance Tips](#performance-tips)
- [Common Operations](#common-operations)

---

## Choosing the Right Collection

### Lists

| Type                   | Use When                    | Avoid When                       |
|------------------------|-----------------------------|----------------------------------|
| `ArrayList`            | Random access, iteration    | Frequent insertions at beginning |
| `LinkedList`           | Queue/deque operations      | Random access (O(n))             |
| `List.of()`            | Immutable, small fixed size | Need to modify                   |
| `CopyOnWriteArrayList` | Few writes, many reads      | Frequent writes                  |

### Sets

| Type            | Use When                     | Avoid When         |
|-----------------|------------------------------|--------------------|
| `HashSet`       | Fast lookup, no order needed | Need ordering      |
| `LinkedHashSet` | Insertion order preservation | Memory constrained |
| `TreeSet`       | Sorted order needed          | Frequent mutations |
| `EnumSet`       | Set of enum values           | Non-enum types     |
| `Set.of()`      | Immutable, small fixed size  | Need to modify     |

### Maps

| Type                | Use When               | Avoid When           |
|---------------------|------------------------|----------------------|
| `HashMap`           | Fast lookup, no order  | Need ordering        |
| `LinkedHashMap`     | Insertion/access order | Memory constrained   |
| `TreeMap`           | Sorted by key          | Frequent mutations   |
| `EnumMap`           | Enum keys              | Non-enum keys        |
| `ConcurrentHashMap` | Multi-threaded access  | Single-threaded only |
| `Map.of()`          | Immutable, ≤10 entries | Need to modify       |

## Initialization Best Practices

### Pre-sizing Collections

```java
// ✅ Pre-size when size is known
List<User> users = new ArrayList<>(expectedSize);
Map<String, User> userMap = new HashMap<>(expectedSize);
Set<String> ids = new HashSet<>(expectedSize);

// Formula for HashMap initial capacity to avoid rehashing
int initialCapacity = (int) (expectedSize / 0.75) + 1;
Map<String, User> map = new HashMap<>(initialCapacity);
```

### Factory Methods (Java 9+)

```java
// Immutable collections - preferred for constants
List<String> statuses = List.of("ACTIVE", "INACTIVE", "PENDING");
Set<Integer> primes = Set.of(2, 3, 5, 7, 11);
Map<String, Integer> scores = Map.of("alice", 100, "bob", 95);

// For more than 10 Map entries
Map<String, Integer> largeMap = Map.ofEntries(
    Map.entry("key1", 1),
    Map.entry("key2", 2),
    // ...
);
```

### Collectors to Immutable

```java
// ✅ Collect to immutable (Java 10+)
List<String> names = users.stream()
    .map(User::name)
    .collect(Collectors.toUnmodifiableList());

// ✅ Java 16+ toList()
List<String> names = users.stream()
    .map(User::name)
    .toList();  // Returns immutable list

// ✅ Collect to Map
Map<String, User> userById = users.stream()
    .collect(Collectors.toUnmodifiableMap(
        User::id,
        Function.identity()
    ));
```

## Performance Tips

### Map Operations

```java
// ✅ computeIfAbsent - atomic get-or-create
cache.computeIfAbsent(key, k -> expensiveComputation(k));

// ❌ Check-then-put (not atomic, wasteful)
if (!cache.containsKey(key)) {
    cache.put(key, expensiveComputation(key));
}

// ✅ getOrDefault for safe access
int count = counts.getOrDefault(key, 0);

// ✅ merge for counting/accumulating
wordCounts.merge(word, 1, Integer::sum);

// ✅ Bulk operations
Map<String, Integer> merged = new HashMap<>(map1);
merged.putAll(map2);  // map2 values override
```

### Iteration Patterns

```java
// ✅ forEach (cleanest for side effects)
map.forEach((key, value) -> process(key, value));

// ✅ entrySet for key-value pairs
for (var entry : map.entrySet()) {
    process(entry.getKey(), entry.getValue());
}

// ❌ Avoid separate key and get calls
for (String key : map.keySet()) {
    User value = map.get(key);  // Extra lookup!
}
```

### Avoiding Common Pitfalls

```java
// ❌ ConcurrentModificationException
for (User user : users) {
    if (user.isInactive()) {
        users.remove(user);  // BOOM!
    }
}

// ✅ Use removeIf
users.removeIf(User::isInactive);

// ✅ Or iterator.remove()
Iterator<User> it = users.iterator();
while (it.hasNext()) {
    if (it.next().isInactive()) {
        it.remove();
    }
}

// ✅ Or collect to new list
List<User> activeUsers = users.stream()
    .filter(u -> !u.isInactive())
    .toList();
```

## Common Operations

### Grouping

```java
// Group by status
Map<Status, List<Order>> byStatus = orders.stream()
    .collect(Collectors.groupingBy(Order::status));

// Group and transform
Map<Status, List<String>> orderIdsByStatus = orders.stream()
    .collect(Collectors.groupingBy(
        Order::status,
        Collectors.mapping(Order::id, Collectors.toList())
    ));

// Group and count
Map<Status, Long> countByStatus = orders.stream()
    .collect(Collectors.groupingBy(
        Order::status,
        Collectors.counting()
    ));
```

### Partitioning

```java
// Split into two groups
Map<Boolean, List<User>> partition = users.stream()
    .collect(Collectors.partitioningBy(User::isActive));

List<User> activeUsers = partition.get(true);
List<User> inactiveUsers = partition.get(false);
```

### Converting Between Collections

```java
// List to Set (removes duplicates)
Set<String> uniqueNames = new HashSet<>(names);

// Set to List (when order matters)
List<String> orderedNames = new ArrayList<>(nameSet);

// Array to List
List<String> list = Arrays.asList(array);  // Fixed-size
List<String> list = new ArrayList<>(Arrays.asList(array));  // Mutable

// List to Array
String[] array = list.toArray(String[]::new);  // Java 11+
String[] array = list.toArray(new String[0]);  // Pre-Java 11
```
