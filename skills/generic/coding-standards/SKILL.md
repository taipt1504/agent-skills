---
name: coding-standards
description: >
  Java 17+ coding standards and patterns — KISS/DRY/SOLID principles, records, sealed classes,
  pattern matching, naming conventions, immutability rules, Optional/Stream best practices,
  error handling with domain exceptions, and code smells.
triggers:
  - Java coding patterns
  - records
  - sealed classes
  - naming conventions
  - immutability
  - Optional
  - Stream
---

# Java Coding Standards & Patterns

## When to Activate

- Writing or reviewing any Java code
- Refactoring for readability or maintainability
- Designing exception hierarchies, domain models, or reactive chains

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

- **Records** — Use for DTOs, value objects, events. Compact constructor for validation. Not for JPA entities or Spring beans.
- **Sealed classes** — Exhaustive type hierarchies: domain events, result types.
- **Pattern matching instanceof** — `if (event instanceof OrderCreatedEvent e)` — no explicit casts.
- **Switch expressions** — `String result = switch (status) { case ACTIVE -> "Active"; ... };`
- **Text blocks** — Multi-line strings for SQL/JSON. No concatenation.

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Class | PascalCase | `OrderService` |
| Method | camelCase, verb-first | `createOrder()` |
| Test method | shouldDoXWhenY | `shouldReturnOrderWhenIdExists()` |
| Constant | UPPER_SNAKE_CASE | `MAX_RETRY_ATTEMPTS` |
| Boolean | is/has/can prefix | `isActive()` |
| Exception | Descriptive + suffix | `OrderNotFoundException` |

## Immutability (Critical)

- Records with `@Builder(toBuilder = true)` and `@With` for updates via new instances.
- Never mutate inside reactive chains — transform with `.map()`.
- Defensive copies: `List.copyOf(items)` in constructors, `List.copyOf()` on getters.
- Use `import` statements — never inline fully-qualified class names.

## Optional & Stream Rules

- **Optional**: Return type only. Never as field, parameter, or collection element. Use `orElseThrow()`, `orElseGet()`, `map()`, `flatMap()`.
- **Streams**: Filter early, use primitive streams for numerics, no side effects, prefer for-loop when readability suffers. Collect to unmodifiable collections.

## Error Handling

- Base `DomainException extends RuntimeException` with error code.
- Specific exceptions: `OrderNotFoundException`, `InsufficientStockException`.
- Reactive: `switchIfEmpty(Mono.error(...))`, `onErrorMap()`, `onErrorResume()` for fallbacks.
- Never throw generic `RuntimeException`. No empty catch blocks.

## Code Smells

| Smell | Fix |
|-------|-----|
| Long method (>30 lines) | Extract named private methods |
| Deep nesting (>3 levels) | Early return / guard clauses |
| Magic numbers | Named constants |
| God class | Split by responsibility |
| N+1 queries | Batch fetch with `findByIdIn()` |

## References

- **[references/java-patterns.md](references/java-patterns.md)** — Immutability (records, @Value, builders, defensive copies), null safety (Optional patterns, @NonNull), concurrency (CompletableFuture, virtual threads, atomic), collections optimization, streams/functional, memory optimization/GC tuning
- **[references/project-structure.md](references/project-structure.md)** — CQRS + Hexagonal package layout, command/query side, shared domain, infrastructure
