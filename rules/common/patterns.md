# Architecture Patterns

Core architectural patterns enforced in this project. For project-specific overrides,
see `PROJECT_GUIDELINES.md` at the project root.

See also: `skills/hexagonal-arch/` for code examples.

**Rule priority**: Project-specific `PROJECT_GUIDELINES.md` > these rules > skill defaults.

---

## Hexagonal Architecture — Layer Boundaries

Dependencies flow **inward only**: Interfaces → Application → Domain ← Infrastructure

```
interfaces/    →  application/  →  domain/
infrastructure/  →  application/  →  domain/
```

| Layer | Allowed Dependencies | Forbidden |
|-------|---------------------|-----------|
| `domain/` | Nothing (pure Java) | Spring, JPA, Kafka, Redis |
| `application/` | `domain/` only | Infrastructure, controllers |
| `infrastructure/` | `domain/`, `application/` | `interfaces/` |
| `interfaces/` | `application/`, `domain/` DTOs | Direct infra access |

**Rule**: Domain entities MUST NOT appear in API responses — map to DTOs at the interfaces layer.

---

## CQRS — Command vs Query Separation

| Side | Responsibility | Returns |
|------|---------------|---------|
| **Command** | Write operations, state changes, event publishing | `Mono<Void>` or `Mono<ID>` |
| **Query** | Read operations, projections | `Mono<DTO>` or `Flux<DTO>` |

- Commands go through use cases (`Create[Entity]UseCase`, `Update[Entity]UseCase`)
- Queries go through query handlers (`Get[Entity]Query`, `Search[Entity]Query`)
- Never mix read and write logic in the same handler

---

## Domain Events

Naming: `{Entity}{PastTense}Event` — e.g., `OrderCreatedEvent`, `PaymentProcessedEvent`

Rules:
- Domain events are **immutable records** — no setters
- Published after successful state change, not before
- Consumers must be **idempotent** — same event delivered twice must be safe
- Use outbox pattern for reliable publishing across service boundaries

---

## Anti-Corruption Layer (ACL)

When integrating with external services or legacy systems:
- Translate external models at the infrastructure boundary
- Domain models must not contain external API types
- Use dedicated mapper/translator classes in `infrastructure/client/`

---

## Reactive Patterns

| Situation | Correct Pattern |
|-----------|----------------|
| Sequential operations | `flatMap` chaining |
| Parallel operations | `Mono.zip` / `Flux.merge` |
| Error recovery | `onErrorResume` / `onErrorReturn` |
| Blocking I/O required | `subscribeOn(Schedulers.boundedElastic())` |
| Retry with backoff | `retryWhen(Retry.backoff(...))` |

**NEVER** call `.block()` — it blocks the event loop thread and causes deadlocks under load.

---

## Package Naming Conventions

```
com.example.{service}/
├── domain/           # Entities, value objects, domain events, repository interfaces (ports)
├── application/      # Use cases, services, command/query handlers
├── infrastructure/   # Repository impls (adapters), Kafka, gRPC, Redis, external clients
└── interfaces/       # Controllers, REST handlers, Kafka event listeners
```

Use cases: `CreateOrderUseCase`, `GetOrderQuery`
Domain exceptions: `OrderNotFoundException`, `PaymentFailedException` (not `RuntimeException`)

---

## Transactional Outbox Pattern

For reliable event publishing across service boundaries:

- Write domain event to `outbox` table in the SAME transaction as the aggregate change
- Separate publisher polls/tails the outbox and publishes to Kafka/RabbitMQ
- Delete outbox row after successful publish (or mark as sent)
- Guarantees at-least-once delivery — consumers MUST be idempotent

Use when: cross-service events, payment notifications, order state changes.

---

## Saga Pattern

For distributed transactions spanning multiple services:

| Type | Orchestration | Choreography |
|------|--------------|--------------|
| **Coordinator** | Central orchestrator service | Each service publishes/listens to events |
| **Compensation** | Orchestrator sends compensating commands | Each service has its own compensation logic |
| **Use when** | Complex flows, clear sequence needed | Simple flows, loose coupling preferred |

Rules:
- Each step must have a compensating action (rollback)
- Use unique saga ID for correlation across services
- Timeout + dead letter for stuck sagas
- Log every step transition for debugging

See `skills/kafka-patterns` for Kafka-based saga implementation details.
