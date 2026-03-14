---
name: hexagonal-arch
description: >
  Hexagonal Architecture (Ports and Adapters) patterns for Java Spring WebFlux applications.
  Covers package structure, dependency rules, port/adapter design, domain modeling (Aggregate
  Root, Value Objects, Domain Events), application layer (Use Cases), infrastructure adapters
  (REST, Kafka, R2DBC), mapping strategies, CQRS integration, and testing by layer.
  Use when designing or refactoring Spring Boot 3.x projects with clean architecture.
---

# Hexagonal Architecture for Spring WebFlux

Ports and Adapters pattern for Java 17+ / Spring Boot 3.x.

## When to Activate

- Creating new modules, services, or bounded contexts
- Reviewing package structure and dependency direction
- Refactoring monolithic code into hexagonal layers
- Planning domain model isolation from infrastructure

## Core Concept

```
          ┌─────────────────────────────────┐
          │          Infrastructure          │
          │  ┌───────────────────────────┐   │
          │  │        Application        │   │
          │  │  ┌─────────────────────┐  │   │
          │  │  │       Domain        │  │   │
          │  │  │  (Business Logic)   │  │   │
          │  │  │  NO external deps   │  │   │
          │  │  └─────────────────────┘  │   │
          │  │  Input Ports ← Use Cases  │   │
          │  │  Output Ports → (ifaces)  │   │
          │  └───────────────────────────┘   │
          │  Input Adapters  Output Adapters  │
          │  (REST, Kafka)   (DB, Kafka, API) │
          └─────────────────────────────────┘
```

## Dependency Rule

**Dependencies point INWARD only:**

```
infrastructure → application → domain
```

| Layer | Can Depend On | Cannot Depend On |
|-------|--------------|------------------|
| **Domain** | Java standard library only | Spring, JPA, R2DBC, Jackson |
| **Application** | Domain | Infrastructure, Spring (except minimal) |
| **Infrastructure** | Application, Domain | — |

## Package Structure

```
src/main/java/com/example/order/
├── domain/                         # Pure business logic, NO framework deps
│   ├── model/                      # Aggregate roots, entities, value objects
│   │   ├── Order.java              # Aggregate Root
│   │   ├── Money.java              # Value Object
│   │   └── OrderStatus.java
│   ├── event/                      # Domain Events
│   └── exception/                  # Domain Exceptions
│
├── application/                    # Use Cases + Application Services
│   ├── port/
│   │   ├── in/                     # Input Ports (interfaces)
│   │   │   ├── CreateOrderUseCase.java
│   │   │   └── dto/               # Commands + Queries
│   │   └── out/                   # Output Ports (interfaces)
│   │       ├── OrderPersistencePort.java
│   │       └── PaymentPort.java
│   └── service/                   # Use Case implementations
│       └── CreateOrderService.java
│
└── infrastructure/                 # Framework-dependent adapters
    ├── adapter/
    │   ├── in/                    # Input Adapters (REST, Kafka consumer)
    │   │   └── rest/OrderController.java
    │   └── out/                   # Output Adapters (DB, Kafka, HTTP)
    │       ├── persistence/OrderPersistenceAdapter.java
    │       └── messaging/OrderKafkaPublisher.java
    └── config/
```

## Domain Layer Essentials

### Aggregate Root (Rich Model — behavior + state)

```java
public class Order {
    private final OrderId id;
    private OrderStatus status;
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    public static Order create(CustomerId customerId, List<OrderItem> items, Address address) {
        if (items == null || items.isEmpty()) throw new InvalidOrderException("Order must have items");
        Order order = new Order(OrderId.generate(), customerId, items, address, OrderStatus.CREATED);
        order.registerEvent(new OrderCreatedEvent(order.id, order.totalAmount));
        return order;
    }

    public void confirm() {
        if (status != OrderStatus.CREATED) throw new InvalidOrderException("Cannot confirm in: " + status);
        this.status = OrderStatus.CONFIRMED;
        registerEvent(new OrderConfirmedEvent(id));
    }

    // No setters — state changes only through business methods
    private void registerEvent(DomainEvent e) { domainEvents.add(e); }
    public List<DomainEvent> getDomainEvents() { return List.copyOf(domainEvents); }
    public void clearDomainEvents() { domainEvents.clear(); }
}
```

### Value Object

```java
public record Money(BigDecimal amount, String currency) {
    public Money {
        Objects.requireNonNull(amount);
        if (amount.scale() > 2) throw new IllegalArgumentException("Scale must be <= 2");
    }
    public Money add(Money other) {
        if (!currency.equals(other.currency)) throw new IllegalArgumentException("Currency mismatch");
        return new Money(amount.add(other.amount), currency);
    }
}
```

## Application Layer Essentials

### Input/Output Ports

```java
// Input Port — what the application exposes
public interface CreateOrderUseCase {
    Mono<OrderResponse> createOrder(CreateOrderCommand command);
}

// Output Port — what the application needs
public interface OrderPersistencePort {
    Mono<Order> save(Order order);
    Mono<Order> findById(OrderId id);
}
public interface PaymentPort {
    Mono<PaymentResult> processPayment(OrderId orderId, Money amount, CustomerId customerId);
}
```

### Use Case (Application Service)

```java
@Service @RequiredArgsConstructor
public class CreateOrderService implements CreateOrderUseCase {
    private final OrderPersistencePort persistence;
    private final PaymentPort payment;
    private final OrderEventPublisherPort eventPublisher;

    @Override
    public Mono<OrderResponse> createOrder(CreateOrderCommand cmd) {
        Order order = Order.create(CustomerId.of(cmd.customerId()), toItems(cmd), toAddress(cmd));
        return persistence.save(order)
            .flatMap(saved -> payment.processPayment(saved.getId(), saved.getTotalAmount(), saved.getCustomerId())
                .flatMap(result -> { if (result.isSuccessful()) saved.confirm(); return persistence.save(saved); }))
            .flatMap(final -> { var events = final.getDomainEvents(); final.clearDomainEvents();
                return eventPublisher.publishEvents(events).thenReturn(final); })
            .map(this::toResponse);
    }
}
```

## Infrastructure Adapters

### Input Adapter — REST

```java
@RestController @RequestMapping("/api/orders") @RequiredArgsConstructor
public class OrderController {
    private final CreateOrderUseCase createOrderUseCase;  // ← depends on PORT, not service

    @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public Mono<OrderResponseDto> create(@Valid @RequestBody CreateOrderRequestDto req) {
        return createOrderUseCase.createOrder(mapper.toCommand(req)).map(mapper::toDto);
    }
}
```

### Output Adapter — Persistence

```java
@Component @RequiredArgsConstructor
public class OrderPersistenceAdapter implements OrderPersistencePort {
    private final OrderR2dbcRepository repository;
    private final OrderPersistenceMapper mapper;

    @Override
    public Mono<Order> save(Order order) {
        return repository.save(mapper.toEntity(order)).map(mapper::toDomain);
    }
}
```

## Mapping Strategy

Three distinct models at each boundary — always explicit mappers:

```
REST DTO ↔ Application Command/Response ↔ Persistence Entity
```

Use MapStruct or manual mappers. Add `Order.reconstitute(...)` factory (bypasses validation, for DB loading).

## Testing by Layer

| Layer | Test Type | What to Mock |
|-------|-----------|-------------|
| Domain | Unit tests | Nothing — pure logic |
| Application | Unit tests | Output ports (mocked) |
| Infrastructure | Integration tests | Nothing (real DB/Kafka) |
| E2E | Full integration | External services (WireMock) |

## Enforce with ArchUnit

```java
@ArchTest
static final ArchRule domain_must_not_depend_on_spring =
    noClasses().that().resideInAPackage("..domain..")
        .should().dependOnClassesThat()
        .resideInAnyPackage("org.springframework..", "jakarta.persistence..", "io.r2dbc..");

@ArchTest
static final ArchRule application_must_not_depend_on_infra =
    noClasses().that().resideInAPackage("..application..")
        .should().dependOnClassesThat().resideInAPackage("..infrastructure..");
```

## When to Use / Not Use

| Use When | Skip When |
|----------|-----------|
| Complex business logic | Simple CRUD |
| Multiple input channels (REST+gRPC+Kafka) | Prototype / PoC |
| Long-lived project | < 3 entities |
| Team > 3 developers | Solo, short deadline |

## References

Load as needed:

- **[references/layers.md](references/layers.md)** — Full domain layer (events, exceptions, typed IDs), full application layer, all infrastructure adapters (Kafka publisher, payment HTTP client, Spring wiring)
- **[references/mapping-testing.md](references/mapping-testing.md)** — MapStruct mappers (REST + Persistence), complete testing examples for all layers, reconstitution pattern
- **[references/cqrs-antipatterns.md](references/cqrs-antipatterns.md)** — CQRS integration (separate command/query ports, read models), full anti-patterns with fixes, key design decisions
