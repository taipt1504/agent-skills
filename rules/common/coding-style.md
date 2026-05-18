---
name: coding-style-common
description: Language-agnostic coding-style rules — immutability, value objects, file size limits, naming patterns, error-handling principles. Applies to all languages.
globs: "*"
applicability:
  always: true
---

# Coding Style — Language-Agnostic

## Immutability First

Mutable state = concurrency bugs. Make illegal states unrepresentable.

- ALWAYS new object, NEVER mutate existing state
- NEVER setters on domain models — derived copies only
- NEVER mutate inside async chains (data races)

## Value Objects — Encode Domain Rules at Type Level

Wrap primitives in self-validating types. Validate at construction → invalid values cannot exist.

## File Size Limits

| Metric | Ideal | Max | Why |
|---|---|---|---|
| File length | 200–400 lines | 800 | Mixed responsibilities → split by concern |
| Method length | ≤30 lines | 50 | Long methods hard to test |
| Nesting depth | ≤3 | 4 | Missing abstractions; use guard clauses |
| Parameters | ≤3 | 5 (use object beyond) | Missing value/command object |

## Naming Patterns

| Concept | Pattern | Example |
|---|---|---|
| Entity | `<Noun>` | `Order` |
| Event | `<Noun><Past>Event` | `OrderCreatedEvent` |
| Use case | `<Verb><Noun>UseCase` | `CreateOrderUseCase` |
| Query | `Get<Noun>Query` | `GetOrderQuery` |
| Test | `should<Do>When<Cond>` | `shouldReturnOrderWhenIdExists` |
| Command method | `<verb><Noun>()` | `createOrder()` |
| Query method | `find<By>()` / `exists<By>()` | `findById()` |

## Error Handling Principles

- Domain exceptions over generic (communicate business intent)
- Log before transforming
- Never swallow silently
- Errors at boundaries; never mask root cause

## Imports

ALWAYS `import` statements. NEVER inline fully-qualified class names in declarations, signatures, bodies, generics. Exception: unavoidable name conflicts.

```java
// BAD
private final org.springframework.transaction.reactive.TransactionalOperator txOp;

// GOOD
import org.springframework.transaction.reactive.TransactionalOperator;
private final TransactionalOperator txOp;
```

## Related

- `rules/java/coding-style.md` — Java/Spring specifics (Lombok, reactive)
- `rules/common/patterns.md` — architecture patterns
