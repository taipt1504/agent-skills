---
name: coding-style
description: Code style rules — immutability, value objects, naming, file limits, error handling, configuration, timeouts
globs: "*.java"
---

# Coding Style

## Core Philosophy: Immutability

Mutable state is the root cause of most concurrency bugs, especially in reactive systems where multiple threads process the same data. Make illegal states unrepresentable.

- ALWAYS create new objects — NEVER mutate existing state
- ALWAYS `@Value` + `@Builder(toBuilder = true)` for domain objects
- NEVER setters on domain models — use `toBuilder().field(value).build()` for derived copies
- NEVER mutate inside reactive chains — create new instances in `map`/`flatMap` (mutable state across async boundaries causes data races)
- Use records for immutable DTOs — they're automatically immutable, have `equals`/`hashCode`, and communicate intent

## Value Objects — Make Illegal States Unrepresentable

Wrap primitives in self-validating value objects to encode domain rules at the type level:

```java
public record Email(String value) {
    public Email {
        if (value == null || !value.matches("^[\\w.-]+@[\\w.-]+\\.[a-zA-Z]{2,}$"))
            throw new IllegalArgumentException("Invalid email: " + value);
    }
}
public record Money(BigDecimal amount, String currency) {
    public Money { Objects.requireNonNull(amount); Objects.requireNonNull(currency); }
}
```

This shifts validation from scattered `if` checks to construction time — invalid values can't exist.

## File Size Limits

| Metric | Ideal | Maximum | Why |
|--------|-------|---------|-----|
| File length | 200–400 lines | 800 lines | Large files indicate mixed responsibilities — split by concern |
| Method length | ≤30 lines | 50 lines | Long methods are hard to test and reason about — extract named methods |
| Nesting depth | ≤3 levels | 4 levels | Deep nesting indicates missing abstractions — use guard clauses or extract |
| Parameters | ≤3 params | 5 (use object beyond) | Many params signal a missing value object or command/query object |

## Naming Conventions

| Concept | Pattern | Example | Why |
|---------|---------|---------|-----|
| Entity | `{Noun}` | `Order`, `OrderItem` | Represents domain concept |
| Event | `{Noun}{Past}Event` | `OrderCreatedEvent` | Past tense = something already happened |
| Use case | `{Verb}{Noun}UseCase` | `CreateOrderUseCase` | Intent-revealing: what it does |
| Query | `{Get}{Noun}Query` | `GetOrderQuery` | Separates reads from writes (CQRS) |
| Test | `should{Do}When{Condition}` | `shouldReturnOrderWhenIdExists` | Reads as specification |
| Command method | `{verb}{Noun}()` | `createOrder()` | Action-oriented |
| Query method | `find{By}()` / `exists{By}()` | `findById()`, `existsByEmail()` | Follows Spring Data conventions |

## Error Handling

- ALWAYS domain exceptions — NEVER generic `RuntimeException` (domain exceptions communicate business rule violations clearly)
- ALWAYS `onErrorResume` / `onErrorMap` in reactive chains — unhandled errors propagate to `onErrorDropped` silently
- ALWAYS log error before transforming: `doOnError(e -> log.error("...", e))`
- NEVER `throw` in `map()` — use `flatMap` + `Mono.error()` (exceptions in `map` bypass reactive error handling)
- NEVER swallow errors silently — every `onErrorResume` must log or re-signal

```java
// BAD — throw in map, no logging
.map(user -> { if (user == null) throw new RuntimeException("not found"); return user; })

// GOOD — domain exception, logging, flatMap
.switchIfEmpty(Mono.error(UserExceptions.NOT_FOUND::toException))
.doOnError(e -> log.error("Failed to load user: userId={}", userId, e))
.onErrorMap(DataAccessException.class, e -> UserExceptions.DB_ERROR.toException())
```

## Configuration Best Practices

- ALWAYS use `@ConfigurationProperties` for type-safe configuration — never scattered `@Value` annotations (type-safe beans catch typos at startup; `@Value` fails silently at runtime)
- ALWAYS configure timeouts for ALL external service calls — a missing timeout causes cascading failures when a dependency is slow:
  ```java
  WebClient.builder()
      .baseUrl(config.getUrl())
      .filter(ExchangeFilterFunctions.timeout(Duration.ofSeconds(5)))
      .build();
  ```
- ALWAYS configure connection pool sizes explicitly — defaults are rarely appropriate for production workloads
- PREFER profile-specific config files (`application-{profile}.yml`) and profile groups for environment separation

## Imports & Dependencies

- ALWAYS use `import` statements — NEVER inline fully-qualified class names (exception: unavoidable name conflicts)
- Lombok: `@Value`, `@Builder`, `@RequiredArgsConstructor`, `@Slf4j` — NEVER `@Data` (it generates setters, violating immutability)
- Constructor injection only via `@RequiredArgsConstructor` — NEVER `@Autowired` on fields (field injection hides dependencies, prevents testing via constructor, and enables circular dependencies)

## Related Skills

- **coding-standards** — Extended Lombok usage table, record DTO examples
- **spring-patterns** — Configuration patterns, WebFlux/MVC specifics
- **architecture** — Package structure, layer responsibility boundaries
