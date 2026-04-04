---
name: architecture
description: >
  Hexagonal architecture, DDD, CQRS, and event sourcing for Java Spring applications.
  Use when designing package structure, creating Aggregate Roots or Value Objects, implementing
  ports and adapters, setting up CQRS command/query separation, wiring domain events,
  writing ArchUnit tests, or creating solution architecture documents and ADRs.
triggers:
  natural: ["hexagonal", "cqrs", "domain event", "package structure", "ports and adapters"]
  code: ["UseCase", "Port", "Adapter", "DomainEvent"]
---

# Architecture — Hexagonal + Solution Design

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

### Aggregate Root Pattern

Rich model with behavior. No setters — state changes through business methods that register domain events.

```java
public class Order {
    private final OrderId id;
    private OrderStatus status;
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    // Factory: new instance (with validation)
    public static Order create(CustomerId customerId, List<OrderLine> lines) {
        Preconditions.requireNonEmpty(lines, "Order must have at least one line");
        var order = new Order(OrderId.generate(), customerId, lines, OrderStatus.CREATED);
        order.registerEvent(new OrderCreatedEvent(order.id, customerId, lines));
        return order;
    }

    // Factory: reconstitute from DB (bypasses validation)
    public static Order reconstitute(OrderId id, CustomerId customerId,
                                      List<OrderLine> lines, OrderStatus status) {
        return new Order(id, customerId, lines, status);
    }

    // Business method: state transition + event
    public void confirm() {
        if (this.status != OrderStatus.CREATED) {
            throw new OrderAlreadyConfirmedException(this.id);
        }
        this.status = OrderStatus.CONFIRMED;
        registerEvent(new OrderConfirmedEvent(this.id));
    }

    private void registerEvent(DomainEvent event) {
        this.domainEvents.add(event);
    }

    public List<DomainEvent> domainEvents() {
        return Collections.unmodifiableList(domainEvents);
    }

    public void clearEvents() {
        domainEvents.clear();
    }
}
```

Key rules: `create()` validates invariants + emits creation event, `reconstitute()` trusts DB data, business methods guard state transitions, events collected and dispatched by application layer.

### Value Objects

Records with compact constructor validation:

```java
public record Money(BigDecimal amount, String currency) {
    public Money {
        Objects.requireNonNull(amount, "amount required");
        Objects.requireNonNull(currency, "currency required");
        if (amount.compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalArgumentException("amount must be non-negative");
        }
    }
    public Money add(Money other) {
        if (!this.currency.equals(other.currency)) throw new CurrencyMismatchException();
        return new Money(this.amount.add(other.amount), this.currency);
    }
}
```

### Typed IDs

```java
public record OrderId(String value) {
    public OrderId { Objects.requireNonNull(value); }
    public static OrderId generate() { return new OrderId(UUID.randomUUID().toString()); }
    public static OrderId of(String value) { return new OrderId(value); }
}
```

## CQRS — Command/Query Separation

### Command Side (Write Path)

```
Controller → Command DTO → CommandHandler (UseCase) → Aggregate → Repository Port → DB
                                                    ↓
                                              DomainEvent → EventPublisher → Kafka/EventStore
```

```java
// Command (immutable record)
public record CreateOrderCommand(String customerId, List<OrderLineDto> lines) {}

// Use case port (application layer interface)
public interface CreateOrderUseCase {
    Mono<OrderId> execute(CreateOrderCommand command);
}

// Handler (application layer implementation)
@RequiredArgsConstructor
public class CreateOrderService implements CreateOrderUseCase {
    private final OrderPersistencePort orderPort;
    private final DomainEventPublisher eventPublisher;

    @Override
    public Mono<OrderId> execute(CreateOrderCommand command) {
        var order = Order.create(
            CustomerId.of(command.customerId()),
            command.lines().stream().map(OrderLineMapper::toDomain).toList()
        );
        return orderPort.save(order)
            .doOnSuccess(saved -> eventPublisher.publishAll(saved.domainEvents()))
            .map(Order::id);
    }
}
```

### Query Side (Read Path)

```
Controller → Query DTO → QueryHandler → ReadModel Repository → Read DB/View
```

```java
// Query use case (separate from command)
public interface GetOrderQuery {
    Mono<OrderDetailResponse> execute(String orderId);
}

// Read model — flat, denormalized, no domain logic
public record OrderDetailResponse(
    String orderId, String customerName, String status,
    BigDecimal totalAmount, LocalDateTime createdAt
) {}
```

Key rules: Command handlers use domain aggregates; query handlers use flat read models directly. Never mix command and query in one handler. Query side can bypass domain layer entirely.

### Domain Event Publisher

```java
// Port (application layer)
public interface DomainEventPublisher {
    void publishAll(List<DomainEvent> events);
}

// Adapter (infrastructure layer — Kafka implementation)
@RequiredArgsConstructor
public class KafkaDomainEventPublisher implements DomainEventPublisher {
    private final KafkaTemplate<String, DomainEvent> kafka;

    @Override
    public void publishAll(List<DomainEvent> events) {
        events.forEach(event -> kafka.send(event.topic(), event.aggregateId(), event));
    }
}
```

## Ports & Adapters Wiring

### Port Definitions (Application Layer)

```java
// Input port — what the outside world can ask
public interface CreateOrderUseCase {
    Mono<OrderId> execute(CreateOrderCommand command);
}

// Output port — what the application needs from infrastructure
public interface OrderPersistencePort {
    Mono<Order> save(Order order);
    Mono<Order> findById(OrderId id);
}

public interface PaymentPort {
    Mono<PaymentResult> charge(OrderId orderId, Money amount);
}
```

### Adapter Implementations (Infrastructure Layer)

```java
// Inbound adapter (REST controller → uses input port)
@RestController
@RequiredArgsConstructor
public class OrderController {
    private final CreateOrderUseCase createOrder;  // depends on PORT, not service

    @PostMapping("/orders")
    public Mono<ResponseEntity<OrderId>> create(@Valid @RequestBody CreateOrderRequest request) {
        return createOrder.execute(OrderMapper.toCommand(request))
            .map(id -> ResponseEntity.created(URI.create("/orders/" + id.value())).body(id));
    }
}

// Outbound adapter (implements output port → talks to DB)
@RequiredArgsConstructor
public class OrderPersistenceAdapter implements OrderPersistencePort {
    private final OrderR2dbcRepository repository;
    private final OrderPersistenceMapper mapper;

    @Override
    public Mono<Order> save(Order order) {
        return repository.save(mapper.toEntity(order)).map(mapper::toDomain);
    }
}
```

### Spring Wiring (Configuration)

```java
@Configuration
public class OrderBeanConfig {
    @Bean
    public CreateOrderUseCase createOrderUseCase(
            OrderPersistencePort orderPort, DomainEventPublisher eventPublisher) {
        return new CreateOrderService(orderPort, eventPublisher);
    }
}
```

## Mapping Strategy

Three models at each boundary — always explicit mappers:

```
REST DTO <-> Application Command/Response <-> Domain <-> Persistence Entity
```

Use MapStruct (`@Mapper(componentModel = "spring")`) or manual mappers. Never let a single model cross boundaries.

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

- **[references/hexagonal-patterns.md](references/hexagonal-patterns.md)** — Full examples: typed IDs, value objects, aggregate root, domain events, application service, adapters (Kafka, HTTP, DB), MapStruct persistence mapper, testing by layer, ArchUnit
- **[references/cqrs-patterns.md](references/cqrs-patterns.md)** — CQRS: command/query separation, read model design, query adapter, anti-patterns
- **[references/solution-design.md](references/solution-design.md)** — Solution Design template + Service Design template (Mermaid diagrams, C4, NFRs, deployment)
- **[references/event-sourcing.md](references/event-sourcing.md)** — Event store design, aggregate root, snapshots, projections, decision matrix

## Related Skills

- **coding-standards** — Package naming, method/class size limits that align with hexagonal layers
- **messaging-patterns** — Event-driven communication between bounded contexts
- **database-patterns** — Repository adapters for persistence layer
- **api-design** — REST interface design for infrastructure adapters
