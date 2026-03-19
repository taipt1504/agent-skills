---
name: coding-style
description: Code style rules — immutability, naming, file limits, error handling, imports
globs: "*.java"
---

# Coding Style

## Immutability (CRITICAL)

- ALWAYS create new objects — NEVER mutate existing state
- ALWAYS `@Value` + `@Builder(toBuilder = true)` for domain objects
- NEVER setters on domain models — use `toBuilder().field(value).build()`
- NEVER mutate inside reactive chains — create new instances in `map`/`flatMap`
- Use records for immutable DTOs

## File Size Limits

| Metric | Ideal | Maximum |
|--------|-------|---------|
| File length | 200–400 lines | 800 lines |
| Method length | ≤30 lines | 50 lines |
| Nesting depth | ≤3 levels | 4 levels |
| Parameters | ≤3 params | 5 (use object beyond) |

## Naming Conventions

| Layer | Pattern | Example |
|-------|---------|---------|
| Entity | `{Noun}` | `Order`, `OrderItem` |
| Event | `{Noun}{Past}Event` | `OrderCreatedEvent` |
| Use case | `{Verb}{Noun}UseCase` | `CreateOrderUseCase` |
| Test method | `should{Do}When{Condition}` | `shouldReturnOrderWhenIdExists` |
| Command | `{verb}{Noun}()` | `createOrder()` |
| Query | `find{By}()` / `exists{By}()` | `findById()` |

## Error Handling

- ALWAYS domain exceptions — NEVER generic `RuntimeException`
- ALWAYS `onErrorResume` / `onErrorMap` in reactive chains
- ALWAYS log error before transforming: `doOnError(e -> log.error(...))`
- NEVER swallow errors silently — NEVER `throw` in `map` (use `flatMap` + `Mono.error()`)

## Imports

- ALWAYS use `import` statements — NEVER inline fully-qualified class names
- Exception: unavoidable name conflicts (two classes with same simple name)
- Lombok: `@Value`, `@Builder`, `@RequiredArgsConstructor` — no `@Data`
- Constructor injection only — no `@Autowired` on fields
