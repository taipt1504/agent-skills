# Coding Style Rules

> This file extends [common/coding-style.md](../common/coding-style.md) with Java specific content.

## Immutability (CRITICAL)

- ALWAYS create new objects — NEVER mutate existing state
- ALWAYS `@Value` + `@Builder(toBuilder = true)` for domain objects
- NEVER setters on domain models — use `toBuilder().field(value).build()`
- NEVER mutate inside reactive chains — create new instances in `map`/`flatMap`

## File Size Limits

| Metric        | Ideal         | Maximum                      |
| ------------- | ------------- | ---------------------------- |
| File length   | 200–400 lines | 800 lines                    |
| Method length | ≤ 30 lines    | 50 lines                     |
| Nesting depth | ≤ 3 levels    | 4 levels                     |
| Parameters    | ≤ 3 params    | 5 params (use object beyond) |

## Naming Conventions

| Layer          | Pattern                       | Example                                      |
| -------------- | ----------------------------- | -------------------------------------------- |
| Entity         | `{Noun}`                      | `Order`, `OrderItem`, `OrderStatus`          |
| Event          | `{Noun}{Past}Event`           | `OrderCreatedEvent`, `PaymentProcessedEvent` |
| Use case       | `{Verb}{Noun}UseCase`         | `CreateOrderUseCase`, `GetOrderQuery`        |
| Service        | `{Noun}Service`               | `OrderService`, `OrderQueryService`          |
| Repo impl      | `{Noun}R2dbcRepository`       | `OrderR2dbcRepository`                       |
| Controller     | `{Noun}Controller`            | `OrderController`                            |
| Test method    | `should{Do}When{Condition}`   | `shouldReturnOrderWhenIdExists`              |
| Command method | `{verb}{Noun}()`              | `createOrder()`, `cancelOrder()`             |
| Query method   | `find{By}()` / `exists{By}()` | `findById()`, `findByStatus()`               |

## Error Handling

- ALWAYS domain exceptions — NEVER generic `RuntimeException`
- ALWAYS `onErrorResume` / `onErrorMap` in reactive chains
- ALWAYS log error before transforming: `doOnError(e -> log.error(...))`
- NEVER swallow errors silently (`onErrorReturn(null)`)
- NEVER `throw` in `map` — use `flatMap` + `Mono.error()`

## Code Quality Checklist

- [ ] Immutability patterns followed (no setters, builders/records)
- [ ] Methods small (≤ 50 lines), classes focused (≤ 400 lines)
- [ ] No deep nesting (> 4 levels)
- [ ] No `System.out.println` or `printStackTrace`
- [ ] No hardcoded magic numbers/strings (use constants)
- [ ] Bean Validation (`@Valid`) on all API inputs
- [ ] Lombok: `@Value`, `@Builder`, `@RequiredArgsConstructor` — no `@Data`
- [ ] No god classes — single responsibility per class
- [ ] No anemic domain models — entities have behavior
- [ ] Constructor injection only — no `@Autowired` on fields

## Detailed Patterns

For code examples and Java 17+ patterns, see:

- `skills/coding-standards` — KISS, DRY, SOLID, records, sealed classes, Optional, Stream
- `skills/hexagonal-arch` — package structure, ports & adapters
