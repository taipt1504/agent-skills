---
name: architecture
description: >
  Hexagonal architecture and solution design patterns for Java Spring WebFlux applications.
  Covers ports and adapters, dependency rules, CQRS integration, domain modeling, mapping
  strategies, testing by layer, ArchUnit enforcement, and solution/service design templates.
triggers:
  - package structure
  - hexagonal layers
  - CQRS
  - domain events
  - aggregate root
  - value objects
  - ArchUnit
---

# Architecture — Hexagonal + Solution Design

## When to Activate

- Creating new modules, services, or bounded contexts
- Reviewing package structure and dependency direction
- Designing system architecture or writing design documents
- Planning domain model isolation from infrastructure

## Hexagonal Layers

```
Infrastructure → Application → Domain (dependencies inward only)
```

| Layer | Can Depend On | Cannot Depend On |
|-------|--------------|------------------|
| **Domain** | Java stdlib only | Spring, JPA, R2DBC, Jackson |
| **Application** | Domain | Infrastructure |
| **Infrastructure** | Application, Domain | — |

### Package Structure

```
com.example.order/
├── domain/          # Aggregates, value objects, events, exceptions, repository interfaces
├── application/     # Use cases (input ports), output port interfaces, services
│   └── port/in/     # CreateOrderUseCase
│   └── port/out/    # OrderPersistencePort, PaymentPort
└── infrastructure/  # REST controllers, DB adapters, Kafka, config
    └── adapter/in/  # OrderController (depends on port, not service)
    └── adapter/out/ # OrderPersistenceAdapter, PaymentApiAdapter
```

## Domain Layer Essentials

- **Aggregate Root**: Rich model with behavior. Factory method `create(...)` for new instances, `reconstitute(...)` for DB loading (bypasses validation). No setters — state changes through business methods that register domain events.
- **Value Objects**: Records with compact constructor validation. E.g., `Money(BigDecimal amount, String currency)`.
- **Typed IDs**: `record OrderId(String value)` with `generate()` and `of()` factories.

## CQRS Overview

Separate command (write, uses domain) from query (read, can bypass domain):

- **Commands**: `CreateOrderCommand` -> `CreateOrderService` -> Domain Aggregate -> Write DB
- **Queries**: `OrderQueryUseCase` -> `OrderQueryService` -> Read Model -> Read DB
- Separate controllers, repositories, and handlers for each side.

## Mapping Strategy

Three models at each boundary — always explicit mappers:

```
REST DTO <-> Application Command/Response <-> Persistence Entity
```

Use MapStruct (`@Mapper(componentModel = "spring")`) or manual mappers.

## Testing by Layer

| Layer | Test Type | What to Mock |
|-------|-----------|-------------|
| Domain | Unit tests | Nothing — pure logic |
| Application | Unit tests | Output ports (mocked) |
| Infrastructure | Integration | Nothing (real DB/Kafka via Testcontainers) |

## ArchUnit Enforcement

Enforce dependency rules with `@ArchTest`: domain must not depend on Spring/JPA, application must not depend on infrastructure, ports must be interfaces.

## When to Use / Skip

**Use**: Complex business logic, multiple input channels, long-lived projects, teams >3.
**Skip**: Simple CRUD, prototypes, <3 entities.

## References

- **[references/hexagonal-patterns.md](references/hexagonal-patterns.md)** — Full examples: typed IDs, value objects, aggregate root, domain events, application service, adapters (Kafka, HTTP, DB), Spring wiring, MapStruct mappers, testing by layer
- **[references/cqrs-patterns.md](references/cqrs-patterns.md)** — CQRS: command/query separation, read model design, query adapter, anti-patterns
- **[references/solution-design.md](references/solution-design.md)** — Solution Design template + Service Design template (Mermaid diagrams, C4, NFRs, deployment)
