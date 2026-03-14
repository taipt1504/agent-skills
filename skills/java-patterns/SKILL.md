---
name: java-patterns
description: Java 17+ best practices, performance patterns, and idioms for production-grade applications. Use when writing new Java code, reviewing existing code, or optimizing performance. Covers immutability, null safety, concurrency, memory optimization, collections, streams, and modern Java features.
---

# Java Patterns & Best Practices

Optimized patterns for Java 17+ production applications.

## Quick Reference

| Category     | When to Use                        | Reference                                     |
|--------------|------------------------------------|-----------------------------------------------|
| Immutability | Domain models, DTOs, Value Objects | [immutability.md](references/immutability.md) |
| Null Safety  | Any nullable data, Optional usage  | [null-safety.md](references/null-safety.md)   |
| Concurrency  | Async operations, thread safety    | [concurrency.md](references/concurrency.md)   |
| Collections  | Lists, Maps, Sets optimization     | [collections.md](references/collections.md)   |
| Streams      | Functional transformations         | [streams.md](references/streams.md)           |
| Memory       | GC tuning, object pooling          | [memory.md](references/memory.md)             |

## Core Principles

### 1. Prefer Immutability

```java
// ✅ Use Records for immutable data
public record User(String id, String name, Instant createdAt) {}

// ✅ Defensive copies for collections
public List<Item> getItems() {
  return List.copyOf(items);
}
```

### 2. Null Safety

```java
// ✅ Optional for nullable returns
public Optional<User> findById(String id) {
  return Optional.ofNullable(userMap.get(id));
}

// ✅ Early validation
public void process(@NonNull String input) {
  Objects.requireNonNull(input, "input must not be null");
}
```

### 3. Modern Java Features (17+)

```java
// ✅ Pattern matching for instanceof
if (obj instanceof String s && s.length() > 0) {
process(s);
}

// ✅ Switch expressions
String result = switch (status) {
  case ACTIVE -> "Active";
  case INACTIVE -> "Inactive";
  case PENDING -> "Pending";
};

// ✅ Text blocks for SQL/JSON
String sql = """
  SELECT id, name
  FROM users
  WHERE status = :status
  """;
```

### 4. Exception Handling

```java
// ✅ Specific exceptions with context
throw new UserNotFoundException("User not found: id=" + id);

// ✅ Try-with-resources
try (var conn = dataSource.getConnection();
var stmt = conn.prepareStatement(sql)) {
  // use resources
  }

// ❌ Never catch Exception/Throwable generically
// ❌ Never swallow exceptions silently
```

### 5. Builder Pattern (for complex objects)

```java
@Builder
public record CreateUserCommand(
  @NonNull String name,
  @NonNull String email,
  @Builder.Default Instant createdAt = Instant.now()
) {}
```

## Performance Checklist

- [ ] Use `StringBuilder` for string concatenation in loops
- [ ] Prefer primitive types over wrappers when possible
- [ ] Use `Map.computeIfAbsent` instead of check-then-put
- [ ] Lazy initialization for expensive objects
- [ ] Avoid unnecessary object creation in hot paths
- [ ] Use parallel streams only for CPU-intensive operations with large data

### 6. Imports Over Fully-Qualified Names

ALWAYS use import statements + short class names. NEVER inline fully-qualified class names in code.

```java
// ❌ WRONG: Fully-qualified names inline
@Bean
public io.f8a.summer.scheduler.store.r2dbc.R2dbcSchemaInitializer schemaInitializer(
    org.springframework.r2dbc.core.DatabaseClient db) {
  return new io.f8a.summer.scheduler.store.r2dbc.R2dbcSchemaInitializer(db, prefix);
}

// ✅ CORRECT: Import + short name
import io.f8a.summer.scheduler.store.r2dbc.R2dbcSchemaInitializer;
import org.springframework.r2dbc.core.DatabaseClient;

@Bean
public R2dbcSchemaInitializer schemaInitializer(DatabaseClient db) {
  return new R2dbcSchemaInitializer(db, prefix);
}
```

**When name conflicts exist**, import the most-used class and qualify the other:

```java
import java.util.Date;

// Only qualify the less-used one
java.sql.Date sqlDate = java.sql.Date.valueOf(localDate);
Date utilDate = new Date();
```

## Anti-Patterns to Avoid

| Anti-Pattern                       | Problem                     | Solution                               |
|------------------------------------|-----------------------------|----------------------------------------|
| Mutable shared state               | Race conditions             | Immutable objects, synchronized access |
| Optional.get() without check       | NPE risk                    | Use orElse/orElseThrow                 |
| Checked exceptions everywhere      | Verbose code                | Use unchecked domain exceptions        |
| Raw types (List without generics)  | Type safety loss            | Always use generics                    |
| String concatenation in loops      | O(n²) performance           | StringBuilder                          |
| Blocking in reactive code          | Thread starvation           | Use reactive operators                 |
| Fully-qualified class names inline | Unreadable code, long lines | Use import statements                  |

## Detailed References

For in-depth patterns and examples:

- **Immutability**: Records, @Value, defensive copies → [references/immutability.md](references/immutability.md)
- **Null Safety**: Optional, @NonNull, validation → [references/null-safety.md](references/null-safety.md)
- **Concurrency**: CompletableFuture, virtual threads, locks → [references/concurrency.md](references/concurrency.md)
- **Collections**: Choosing right collection, capacity,
  iteration → [references/collections.md](references/collections.md)
- **Streams**: Parallel streams, collectors, performance → [references/streams.md](references/streams.md)
- **Memory**: Object pooling, GC tuning, profiling → [references/memory.md](references/memory.md)
