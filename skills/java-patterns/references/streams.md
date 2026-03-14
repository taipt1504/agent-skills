# Streams Patterns

## Table of Contents

- [Basic Operations](#basic-operations)
- [Collectors](#collectors)
- [Parallel Streams](#parallel-streams)
- [Performance Considerations](#performance-considerations)

---

## Basic Operations

### Transformation

```java
// map - transform each element
List<String> names = users.stream()
    .map(User::name)
    .toList();

// flatMap - one-to-many transformation
List<Order> allOrders = users.stream()
    .flatMap(user -> user.orders().stream())
    .toList();

// mapMulti (Java 16+) - efficient flatMap alternative
List<Order> orders = users.stream()
    .<Order>mapMulti((user, consumer) -> {
        if (user.isActive()) {
            user.orders().forEach(consumer);
        }
    })
    .toList();
```

### Filtering

```java
// filter - keep matching elements
List<User> activeUsers = users.stream()
    .filter(User::isActive)
    .toList();

// takeWhile (Java 9+) - take elements while condition is true
List<Integer> upToFive = numbers.stream()
    .takeWhile(n -> n < 5)
    .toList();

// dropWhile (Java 9+) - skip elements while condition is true
List<Integer> afterFive = numbers.stream()
    .dropWhile(n -> n < 5)
    .toList();

// distinct - remove duplicates (uses equals())
List<String> unique = names.stream()
    .distinct()
    .toList();
```

### Finding

```java
// findFirst - first element
Optional<User> first = users.stream()
    .filter(User::isAdmin)
    .findFirst();

// findAny - any element (better for parallel)
Optional<User> any = users.parallelStream()
    .filter(User::isAdmin)
    .findAny();

// anyMatch, allMatch, noneMatch
boolean hasAdmin = users.stream().anyMatch(User::isAdmin);
boolean allActive = users.stream().allMatch(User::isActive);
boolean noneDeleted = users.stream().noneMatch(User::isDeleted);
```

### Reducing

```java
// sum
int total = orders.stream()
    .mapToInt(Order::quantity)
    .sum();

// max/min
Optional<User> oldest = users.stream()
    .max(Comparator.comparing(User::age));

// reduce - custom reduction
BigDecimal total = orders.stream()
    .map(Order::amount)
    .reduce(BigDecimal.ZERO, BigDecimal::add);

// Complex reduction with identity
int sumOfSquares = numbers.stream()
    .reduce(0, (acc, n) -> acc + n * n, Integer::sum);
```

## Collectors

### Basic Collectors

```java
// toList, toSet
List<String> list = stream.collect(Collectors.toList());
Set<String> set = stream.collect(Collectors.toSet());

// toMap
Map<String, User> byId = users.stream()
    .collect(Collectors.toMap(User::id, Function.identity()));

// toMap with merge function (handles duplicates)
Map<String, User> latest = users.stream()
    .collect(Collectors.toMap(
        User::id,
        Function.identity(),
        (existing, replacement) -> replacement  // Keep latest
    ));

// toMap with specific map implementation
Map<String, User> sorted = users.stream()
    .collect(Collectors.toMap(
        User::id,
        Function.identity(),
        (a, b) -> a,
        TreeMap::new
    ));
```

### Grouping Collectors

```java
// groupingBy
Map<Status, List<Order>> byStatus = orders.stream()
    .collect(Collectors.groupingBy(Order::status));

// groupingBy with downstream collector
Map<Status, Long> countByStatus = orders.stream()
    .collect(Collectors.groupingBy(
        Order::status,
        Collectors.counting()
    ));

// groupingBy with summing
Map<Status, Integer> quantityByStatus = orders.stream()
    .collect(Collectors.groupingBy(
        Order::status,
        Collectors.summingInt(Order::quantity)
    ));

// Nested grouping
Map<Region, Map<Status, List<Order>>> nested = orders.stream()
    .collect(Collectors.groupingBy(
        Order::region,
        Collectors.groupingBy(Order::status)
    ));
```

### String Collectors

```java
// joining
String csv = names.stream()
    .collect(Collectors.joining(", "));

// joining with prefix/suffix
String json = names.stream()
    .collect(Collectors.joining("\", \"", "[\"", "\"]"));
```

### Statistics

```java
// Summarizing
IntSummaryStatistics stats = orders.stream()
    .collect(Collectors.summarizingInt(Order::quantity));

int count = stats.getCount();
int sum = stats.getSum();
double avg = stats.getAverage();
int max = stats.getMax();
int min = stats.getMin();
```

## Parallel Streams

### When to Use

```
✅ Use parallel streams when:
- Large data sets (>10,000 elements)
- CPU-intensive operations
- Independent operations (no shared mutable state)
- Order doesn't matter

❌ Avoid parallel streams when:
- Small data sets
- I/O-bound operations
- Operations have side effects
- Order matters (use .forEachOrdered)
- Inside reactive/async code
```

### Correct Usage

```java
// ✅ Good parallel stream usage
long count = largeList.parallelStream()
    .filter(item -> expensiveCheck(item))
    .count();

// ✅ With ordered terminal operation when order matters
List<Result> results = largeList.parallelStream()
    .map(this::process)
    .sorted()
    .collect(Collectors.toList());

// ❌ Bad: Shared mutable state
List<User> result = new ArrayList<>();
users.parallelStream()
    .filter(User::isActive)
    .forEach(result::add);  // NOT THREAD-SAFE!

// ✅ Fixed: Use collector
List<User> result = users.parallelStream()
    .filter(User::isActive)
    .collect(Collectors.toList());
```

## Performance Considerations

### Avoid Stream Overhead for Simple Cases

```java
// ❌ Overkill for simple iteration
users.stream().forEach(this::process);

// ✅ Simpler and often faster
users.forEach(this::process);

// ❌ Overkill for checking empty
users.stream().findAny().isPresent();

// ✅ Direct check
!users.isEmpty();
```

### Optimize Intermediate Operations

```java
// ✅ Filter early to reduce downstream work
users.stream()
    .filter(User::isActive)        // Filter first
    .map(this::expensiveTransform) // Then transform
    .toList();

// ✅ Use primitive streams for numerics
int sum = orders.stream()
    .mapToInt(Order::quantity)  // Avoids boxing
    .sum();

// ❌ Avoid: Boxing overhead
Integer sum = orders.stream()
    .map(Order::quantity)       // Boxes to Integer
    .reduce(0, Integer::sum);   // More boxing
```

### Short-Circuiting Operations

```java
// ✅ Stop early when possible
boolean hasAdmin = users.stream()
    .anyMatch(User::isAdmin);  // Stops at first match

// ✅ limit for large/infinite streams
List<User> sample = hugeList.stream()
    .filter(User::isActive)
    .limit(10)
    .toList();
```
