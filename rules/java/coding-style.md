---
name: coding-style-java
description: Java/Spring-specific coding-style rules — Lombok, constructor injection, reactive error handling, configuration timeouts.
globs: "*.java"
applicability:
  always: false
  triggers:
    files_match: ["**/*.java"]
    task_keywords: ["java", "spring", "lombok"]
---

# Coding Style — Java/Spring

> Inherits all rules from `rules/common/coding-style.md`. Below = Java-specific additions.

## Lombok

- `@Value`, `@Builder(toBuilder = true)` for domain objects
- `@RequiredArgsConstructor` for DI (constructor injection)
- `@Slf4j` for loggers
- NEVER `@Data` — generates setters, violates immutability

## Records over POJOs

Records for immutable DTOs. Auto `equals`/`hashCode`. Communicate intent.

```java
public record Email(String value) {
    public Email {
        if (value == null || !value.matches("^[\\w.-]+@[\\w.-]+\\.[a-zA-Z]{2,}$"))
            throw new IllegalArgumentException("Invalid email: " + value);
    }
}
```

## DI — Constructor Injection Only

`@RequiredArgsConstructor`. NEVER `@Autowired` on fields — hides deps, prevents constructor testing, enables circular deps.

## Reactive Error Handling

- `onErrorResume` / `onErrorMap` on every chain
- NEVER `throw` in `map()` — use `flatMap` + `Mono.error()`
- `doOnError(e -> log.error("...", e))` before transforming

```java
// BAD
.map(user -> { if (user == null) throw new RuntimeException("not found"); return user; })

// GOOD
.switchIfEmpty(Mono.error(UserExceptions.NOT_FOUND::toException))
.doOnError(e -> log.error("Failed to load user: userId={}", userId, e))
.onErrorMap(DataAccessException.class, e -> UserExceptions.DB_ERROR.toException())
```

## Configuration

- `@ConfigurationProperties` for type-safe config — NEVER scattered `@Value`
- ALL external calls: explicit timeout; connection pools: explicit sizes
- Profile-specific: `application-<profile>.yml`

```java
WebClient.builder()
    .baseUrl(config.getUrl())
    .filter(ExchangeFilterFunctions.timeout(Duration.ofSeconds(5)))
    .build();
```

## Related

- `rules/java/reactive.md` — no .block(), backpressure
- `rules/java/api-design.md` — REST conventions
- `skills/spring-webflux-patterns` / `skills/spring-mvc-patterns`
