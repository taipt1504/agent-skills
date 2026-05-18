---
name: architecture-patterns
description: Architecture rules — hexagonal layers, DDD tactical patterns, CQRS, reactive rules, ArchUnit enforcement
globs: "*.java"
---

# Architecture Patterns

## Hexagonal Architecture

Dependencies flow **inward only**: Interfaces → Application → Domain ← Infrastructure

| Layer | Allowed Dependencies | Forbidden | Why |
|-------|---------------------|-----------|-----|
| `domain/` | Java stdlib only | Spring, JPA, R2DBC, Kafka, Redis, Jackson | Pure business logic — framework coupling kills reuse and testability |
| `application/` | `domain/` only | Infrastructure, controllers | Use cases orchestrate domain; don't know HOW things are stored/delivered |
| `infrastructure/` | `domain/`, `application/` | `interfaces/` | Adapters implement ports; adapt technology to domain contracts |
| `interfaces/` | `application/`, `domain/` DTOs | Direct infra access | Controllers delegate to use cases; never bypass application layer |

Domain entities MUST NOT appear in API responses — map to record DTOs at interfaces layer. Exposing entities leaks persistence details (lazy loading proxies, internal IDs, audit fields) and couples API contracts to DB schema.

### Use Case Design

- Each use case = one atomic operation — one transaction, one responsibility
- Use cases MUST NOT call other use cases — creates fragile dependency chains where changes cascade
- Share behavior through **domain services** (stateless logic) or **domain events** (async coordination)
- Name by intent: `CreateOrderUseCase`, `GetOrderQuery` — not `OrderService`

### When to Use / Skip Hexagonal

| Use When | Skip When |
|----------|-----------|
| Complex business logic with multiple rules | Simple CRUD with <3 entities |
| Multiple input channels (REST, CLI, messaging) | Single REST API, no plans to grow |
| Long-lived system (>2 years) | Prototype or MVP |
| Team >3 developers | Solo developer, small scope |

## DDD Tactical Patterns

### Aggregate Design (Vaughn Vernon's Rules)

Aggregates enforce consistency boundaries — all invariants checked within aggregate root:

1. **Reference other aggregates by ID only** — object references accidentally load half system, prevent transaction isolation.
2. **Design small aggregates** — if it won't fit on whiteboard, too large. Target ≤5 entities per aggregate.
3. **State changes through domain methods** — `order.confirm()` not `order.setStatus(CONFIRMED)`. Domain methods enforce invariants; setters bypass them.
4. **Factory method for creation** — `Order.create(...)` validates and registers `OrderCreatedEvent`; `Order.reconstitute(...)` for DB loading (bypasses validation).
5. **Immutable events** — domain events are records: `OrderCreatedEvent(orderId, items, total, timestamp)`. Never modify published events.

### Value Objects

Wrap primitives in value objects to make illegal states unrepresentable:

```java
// BAD — any string is a valid "email"
public Mono<User> createUser(String email, String phone) { ... }

// GOOD — Email and PhoneNumber enforce format rules at construction
public Mono<User> createUser(Email email, PhoneNumber phone) { ... }
```

Value objects: immutable (records), equality by value (not identity), self-validating (compact constructor throws on invalid input).

## CQRS

| Side | Responsibility | Returns | Transaction |
|------|---------------|---------|-------------|
| Command | Write, state changes, domain events | `Mono<Void>` or `Mono<ID>` | Read-write |
| Query | Read, projections, no side effects | `Mono<DTO>` or `Flux<DTO>` | Read-only (`@Transactional(readOnly=true)`) |

Never mix read and write logic in same handler. Separate controllers, repositories, handlers per side — enables independent scaling (read replicas, denormalized views).

**When NOT to use CQRS**: simple CRUD, prototypes, strong consistency without eventual consistency tolerance, teams without event-driven experience.

## Domain Events & Outbox

- Events = **immutable records** named `{Entity}{PastTense}Event` (e.g., `OrderCreatedEvent`)
- Publish after successful state change; consumers MUST be **idempotent**
- **Outbox pattern**: write event to `outbox_events` in SAME transaction as aggregate change — guarantees at-least-once delivery without distributed transactions
- Separate **domain events** (internal, bounded context) from **integration events** (cross-service)

## Reactive Rules

| NEVER | WHY | FIX |
|-------|-----|-----|
| `.block()` / `.blockFirst()` / `.blockLast()` | Blocks Netty event loop → deadlocks all concurrent requests | Compose with `flatMap`/`then`/`zip` |
| `Thread.sleep()` | Same event loop blocking as `.block()` | `Mono.delay(Duration)` |
| `RestTemplate` | Blocking HTTP client on reactive stack | `WebClient` (non-blocking) |
| `.subscribe()` inside reactive chain | Fire-and-forget loses error handling and backpressure | `flatMap`/`then` to compose |
| Mutable state in `map`/`flatMap` | Shared mutable state across async boundaries → data races | Immutable types; Reactor `Context` for per-request data |

| ALWAYS | WHY |
|--------|-----|
| `StepVerifier` for testing reactive code | Only reliable way to test async sequences — never `Thread.sleep` in tests |
| `switchIfEmpty(Mono.defer(...))` for empty handling | Without `defer`, the fallback evaluates eagerly — defeating lazy evaluation |
| `onErrorResume`/`onErrorMap` for error recovery | Unhandled errors in reactive chains propagate silently to `onErrorDropped` |
| `limitRate()`/`buffer()` for unbounded `Flux` | Without backpressure, fast producers overwhelm slow consumers → OOM |
| `Schedulers.boundedElastic()` for blocking I/O wrappers | `parallel()` scheduler is for CPU work — blocking on it starves compute threads |

## ArchUnit Enforcement

Enforce dependency rules as executable tests — prevents architecture drift:

```java
@ArchTest
static final ArchRule domainMustNotDependOnSpring =
    noClasses().that().resideInAPackage("..domain..")
        .should().dependOnClassesThat().resideInAPackage("org.springframework..");

@ArchTest
static final ArchRule applicationMustNotDependOnInfrastructure =
    noClasses().that().resideInAPackage("..application..")
        .should().dependOnClassesThat().resideInAPackage("..infrastructure..");

@ArchTest
static final ArchRule portsMustBeInterfaces =
    classes().that().resideInAPackage("..port..")
        .should().beInterfaces();
```

## Related Skills

- **architecture** — Full hexagonal patterns, CQRS details, solution design templates
- **coding-standards** — Package naming, method/class size limits
- **messaging-patterns** — Event-driven bounded context communication, saga patterns
- **database-patterns** — Repository adapter patterns, R2DBC/JPA
