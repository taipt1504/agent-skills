---
name: coding-standards
description: >
  Java 17+ coding standards — records, sealed classes, pattern matching, SOLID principles,
  naming conventions, immutability rules, Optional/Stream best practices, domain exceptions,
  and code smell detection. Use when writing new Java classes, reviewing code quality,
  refactoring for immutability, or enforcing naming conventions in a Spring Boot project.
triggers:
  natural: ["naming convention", "java pattern", "code style", "immutability", "records"]
  code: ["*.java"]
applicability:
  always: true
  triggers:
    files_match: ["**/*.java"]
    code_patterns: ["@Value", "@RequiredArgsConstructor", "record", "@Builder"]
    task_keywords: ["coding style", "immutability", "naming", "records", "Lombok"]
    related_rules:
      - rules/common/coding-style.md
      - rules/java/coding-style.md
relevance_assessment: |
  Always 100% when project has Java files — applies to every code change.
---

# Java Coding Standards & Patterns

## Core Principles

| Principle | Rule |
|-----------|------|
| **Readability First** | Self-documenting names over comments |
| **KISS** | Simplest solution that works |
| **DRY** | Extract repeated logic |
| **YAGNI** | No speculative features |
| **Single Responsibility** | One class/method = one purpose |
| **SOLID** | Open/closed, Liskov, interface segregation, dependency inversion |

## Java 17+ Features

- **Records** — DTOs, value objects, events. Compact constructor for validation. Not for JPA entities or Spring beans.
- **Sealed classes** — Exhaustive type hierarchies: domain events, result types.
- **Pattern matching instanceof** — `if (event instanceof OrderCreatedEvent e)` — no explicit casts.
- **Switch expressions** — `String result = switch (status) { case ACTIVE -> "Active"; ... };`
- **Text blocks** — Multi-line SQL/JSON strings. No concatenation.

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Class | PascalCase | `OrderService` |
| Method | camelCase, verb-first | `createOrder()` |
| Test method | shouldDoXWhenY | `shouldReturnOrderWhenIdExists()` |
| Constant | UPPER_SNAKE_CASE | `MAX_RETRY_ATTEMPTS` |
| Boolean | is/has/can prefix | `isActive()` |
| Exception | Descriptive + suffix | `OrderNotFoundException` |

## Lombok Usage

| Annotation | When to Use | Avoid When |
|-----------|-------------|------------|
| `@RequiredArgsConstructor` | Spring beans (services, controllers) | DTOs (use records) |
| `@Value` | Immutable non-record classes (JPA entities) | When record works |
| `@Builder(toBuilder=true)` | Complex construction (≥3 fields) | Simple 1-2 field objects |
| `@Slf4j` | Any class that logs | — |

**Prefer records over Lombok for DTOs/value objects.**

```java
// GOOD: record DTO + Lombok service
public record CreateOrderRequest(@NotBlank String productId, @Positive int quantity) {}

@Service @RequiredArgsConstructor @Slf4j
public class OrderService {
    private final OrderRepository orderRepository;
}
```

## Immutability (Critical)

- Records with `@Builder(toBuilder = true)` and `@With` for updates via new instances.
- Never mutate inside reactive chains — transform with `.map()`.
- Defensive copies: `List.copyOf(items)` in constructors and getters.

## Optional & Stream Rules

- **Optional**: Return type only. Never field, parameter, or collection element. Use `orElseThrow()`, `orElseGet()`, `map()`, `flatMap()`.
- **Streams**: Filter early, primitive streams for numerics, no side effects, for-loop when readability suffers. Collect to unmodifiable.

## Error Handling

- Base `DomainException extends RuntimeException` with error code.
- Specific exceptions: `OrderNotFoundException`, `InsufficientStockException`.
- Reactive: `switchIfEmpty(Mono.error(...))`, `onErrorMap()`, `onErrorResume()`.
- Never generic `RuntimeException`. No empty catch blocks.

## Code Smells

| Smell | Fix |
|-------|-----|
| Long method (>50 lines) | Extract named private methods |
| Deep nesting (>3 levels) | Early return / guard clauses |
| Magic numbers | Named constants |
| God class | Split by responsibility |
| N+1 queries | Batch fetch with `findByIdIn()` |

## References

- **[references/java-patterns.md](references/java-patterns.md)** — Immutability (records, @Value, builders, defensive copies), null safety (Optional patterns, @NonNull), concurrency (atomic variables, thread-safe collections), collections optimization, streams/functional

## Related Skills

- **spring-webflux-patterns** — Controller/handler patterns using these conventions
- **architecture** — Hexagonal layer rules complement coding standards
- **testing-workflow** — Test naming conventions, TDD cycle
