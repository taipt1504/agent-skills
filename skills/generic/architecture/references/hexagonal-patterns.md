# Hexagonal Architecture Patterns Reference

Complete domain, application, and infrastructure layer examples.

## Table of Contents
- [Domain Layer — Full Examples](#domain-layer--full-examples)
- [Application Layer — Full Use Case](#application-layer--full-use-case)
- [Infrastructure — Kafka Publisher](#infrastructure--kafka-publisher)
- [Infrastructure — External HTTP Adapter](#infrastructure--external-http-adapter)
- [Spring Wiring](#spring-wiring)
- [MapStruct Mappers](#mapstruct-mappers)
- [Reconstitution Pattern](#reconstitution-pattern)
- [Testing by Layer](#testing-by-layer)
- [ArchUnit Enforcement](#archunit-enforcement)

---

## Domain Layer — Full Examples

### Typed IDs (Value Objects)

```java
public record OrderId(String value) {
    public OrderId { Objects.requireNonNull(value); if (value.isBlank()) throw new IllegalArgumentException(); }
    public static OrderId generate() { return new OrderId(UUID.randomUUID().toString()); }
    public static OrderId of(String value) { return new OrderId(value); }
}

public record CustomerId(String value) {
    public CustomerId { Objects.requireNonNull(value); }
    public static CustomerId of(String value) { return new CustomerId(value); }
}
```

### Money Value Object

```java
public record Money(BigDecimal amount, String currency) {
    public static final Money ZERO = new Money(BigDecimal.ZERO, "USD");
    public Money {
        Objects.requireNonNull(amount); Objects.requireNonNull(currency);
        if (amount.scale() > 2) throw new IllegalArgumentException("Scale must be <= 2");
    }
    public Money add(Money other) { requireSameCurrency(other); return new Money(amount.add(other.amount), currency); }
    public Money multiply(int qty) { return new Money(amount.multiply(BigDecimal.valueOf(qty)), currency); }
    private void requireSameCurrency(Money other) {
        if (!currency.equals(other.currency)) throw new IllegalArgumentException("Currency mismatch");
    }
}
```

### Aggregate Root

```java
public class Order {
    private final OrderId id;
    private final CustomerId customerId;
    private final List<OrderItem> items;
    private OrderStatus status;
    private Money totalAmount;
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    public static Order create(CustomerId customerId, List<OrderItem> items, Address address) {
        if (items == null || items.isEmpty()) throw new InvalidOrderException("Must have items");
        Order order = new Order(OrderId.generate(), customerId, List.copyOf(items),
            address, OrderStatus.CREATED, calculateTotal(items), Instant.now(), Instant.now());
        order.registerEvent(new OrderCreatedEvent(order.id, order.customerId, order.totalAmount, order.createdAt));
        return order;
    }

    // Reconstitution — for DB loading (bypasses business validation)
    public static Order reconstitute(OrderId id, CustomerId customerId, List<OrderItem> items,
            Address address, OrderStatus status, Money totalAmount, Instant createdAt, Instant updatedAt) {
        return new Order(id, customerId, items, address, status, totalAmount, createdAt, updatedAt);
    }

    public void confirm() {
        if (status != OrderStatus.CREATED) throw new InvalidOrderException("Cannot confirm in: " + status);
        this.status = OrderStatus.CONFIRMED;
        registerEvent(new OrderConfirmedEvent(id, totalAmount));
    }

    public void cancel(String reason) {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED)
            throw new InvalidOrderException("Cannot cancel in: " + status);
        this.status = OrderStatus.CANCELLED;
        registerEvent(new OrderCancelledEvent(id, reason));
    }

    // No setters — state changes through business methods only
    private void registerEvent(DomainEvent e) { domainEvents.add(e); }
    public List<DomainEvent> getDomainEvents() { return List.copyOf(domainEvents); }
    public void clearDomainEvents() { domainEvents.clear(); }
}
```

### Domain Events

```java
public interface DomainEvent { Instant occurredAt(); }

public record OrderCreatedEvent(OrderId orderId, CustomerId customerId,
        Money totalAmount, Instant occurredAt) implements DomainEvent {}
public record OrderConfirmedEvent(OrderId orderId, Money totalAmount, Instant occurredAt)
        implements DomainEvent {}
public record OrderCancelledEvent(OrderId orderId, String reason, Instant occurredAt)
        implements DomainEvent {}
```

---

## Application Layer — Full Use Case

```java
@Service @RequiredArgsConstructor @Slf4j
public class CreateOrderService implements CreateOrderUseCase {
    private final OrderPersistencePort orderPersistence;
    private final PaymentPort paymentPort;
    private final OrderEventPublisherPort eventPublisher;

    @Override
    public Mono<OrderResponse> createOrder(CreateOrderCommand cmd) {
        Order order = Order.create(CustomerId.of(cmd.customerId()), toItems(cmd), toAddress(cmd));
        return orderPersistence.save(order)
            .flatMap(saved -> paymentPort.processPayment(saved.getId(), saved.getTotalAmount(), saved.getCustomerId())
                .flatMap(result -> {
                    if (result.isSuccessful()) saved.confirm(); else saved.cancel("Payment failed");
                    return orderPersistence.save(saved);
                }))
            .flatMap(finalOrder -> {
                var events = finalOrder.getDomainEvents(); finalOrder.clearDomainEvents();
                return eventPublisher.publishEvents(events).thenReturn(finalOrder);
            })
            .map(this::toResponse);
    }
}
```

---

## Infrastructure — Kafka Publisher

```java
@Component @RequiredArgsConstructor @Slf4j
public class OrderKafkaPublisher implements OrderEventPublisherPort {
    private final KafkaTemplate<String, Object> kafkaTemplate;

    @Override
    public Mono<Void> publishEvents(List<DomainEvent> events) {
        return Flux.fromIterable(events).flatMap(this::publishEvent).then();
    }

    private Mono<Void> publishEvent(DomainEvent event) {
        String topic = switch (event) {
            case OrderCreatedEvent e -> "order.created";
            case OrderConfirmedEvent e -> "order.confirmed";
            case OrderCancelledEvent e -> "order.cancelled";
            default -> "order.events";
        };
        return Mono.fromFuture(kafkaTemplate.send(topic, resolveKey(event), event))
            .doOnError(e -> log.error("Failed to publish {}", event, e)).then();
    }
}
```

---

## Infrastructure — External HTTP Adapter

```java
@Component @RequiredArgsConstructor
public class PaymentApiAdapter implements PaymentPort {
    private final WebClient paymentWebClient;

    @Override
    public Mono<PaymentResult> processPayment(OrderId orderId, Money amount, CustomerId customerId) {
        return paymentWebClient.post().uri("/api/payments")
            .bodyValue(new PaymentRequest(orderId.value(), customerId.value(), amount.amount(), amount.currency()))
            .retrieve().bodyToMono(PaymentApiResponse.class)
            .map(r -> new PaymentResult(r.isSuccess(), r.transactionId(), r.failureReason()))
            .onErrorResume(WebClientResponseException.class,
                e -> Mono.just(PaymentResult.failed("API error: " + e.getStatusCode())))
            .timeout(Duration.ofSeconds(10))
            .onErrorResume(TimeoutException.class, e -> Mono.just(PaymentResult.failed("Timeout")));
    }
}
```

---

## Spring Wiring

```java
@Configuration
public class BeanConfig {
    @Bean
    public WebClient paymentWebClient() {
        return WebClient.builder()
            .baseUrl("http://payment-service:8080")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .build();
    }
}
// Input adapter wiring: Port -> @Service is automatically injected via constructor injection
```

---

## MapStruct Mappers

### REST Mapper

```java
@Mapper(componentModel = "spring")
public interface OrderRestMapper {
    @Mapping(target = "orderId", source = "id.value")
    @Mapping(target = "totalAmount", source = "totalAmount.amount")
    OrderResponse toResponse(Order order);

    CreateOrderCommand toCommand(CreateOrderRequest request);
}
```

### Persistence Mapper

```java
@Mapper(componentModel = "spring")
public interface OrderPersistenceMapper {
    @Mapping(target = "id", source = "id.value")
    @Mapping(target = "totalAmount", source = "totalAmount.amount")
    OrderEntity toEntity(Order order);

    default Order toDomain(OrderEntity entity) {
        return Order.reconstitute(
            OrderId.of(entity.getId()),
            CustomerId.of(entity.getCustomerId()),
            entity.getItems().stream().map(this::toItemDomain).toList(),
            toAddressDomain(entity),
            OrderStatus.valueOf(entity.getStatus()),
            new Money(entity.getTotalAmount(), entity.getCurrency()),
            entity.getCreatedAt(), entity.getUpdatedAt());
    }
}
```

---

## Testing by Layer

### Domain Unit Tests (pure POJO, no Spring)

```java
@Test
void shouldCreateOrderWithValidItems() {
    var order = Order.create(CustomerId.of("c-1"),
        List.of(new OrderItem(ProductId.of("P1"), 2, new Money(new BigDecimal("10.00"), "USD"))),
        someAddress());
    assertThat(order.getStatus()).isEqualTo(OrderStatus.CREATED);
    assertThat(order.getDomainEvents()).hasSize(1).first().isInstanceOf(OrderCreatedEvent.class);
}

@Test
void shouldRejectEmptyItems() {
    assertThatThrownBy(() -> Order.create(CustomerId.of("c-1"), List.of(), someAddress()))
        .isInstanceOf(InvalidOrderException.class);
}
```

### Application Tests (mocked ports)

```java
@ExtendWith(MockitoExtension.class)
class CreateOrderServiceTest {
    @Mock OrderPersistencePort persistence;
    @Mock PaymentPort payment;
    @Mock OrderEventPublisherPort publisher;
    @InjectMocks CreateOrderService service;

    @Test
    void shouldConfirmOnSuccessfulPayment() {
        when(persistence.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(payment.processPayment(any(), any(), any())).thenReturn(Mono.just(PaymentResult.success("tx-1")));
        when(publisher.publishEvents(anyList())).thenReturn(Mono.empty());

        StepVerifier.create(service.createOrder(validCommand()))
            .expectNextMatches(r -> r.status() == OrderStatus.CONFIRMED)
            .verifyComplete();
    }
}
```

### Infrastructure Integration Tests (Testcontainers)

```java
@DataR2dbcTest @Testcontainers
class OrderR2dbcAdapterTest {
    @Container static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");
    @DynamicPropertySource static void props(DynamicPropertyRegistry r) { /* bind r2dbc url */ }

    @Test void shouldSaveAndFindOrder() {
        StepVerifier.create(adapter.save(order).flatMap(s -> adapter.findById(s.getId())))
            .expectNextMatches(found -> found.getStatus() == OrderStatus.CREATED)
            .verifyComplete();
    }
}
```

---

## ArchUnit Enforcement

```java
@AnalyzeClasses(packages = "com.example.order")
class ArchitectureTest {
    @ArchTest ArchRule domainNoSpring = noClasses().that().resideInAPackage("..domain..")
        .should().dependOnClassesThat().resideInAnyPackage("org.springframework..", "jakarta.persistence..");

    @ArchTest ArchRule appNoInfra = noClasses().that().resideInAPackage("..application..")
        .should().dependOnClassesThat().resideInAPackage("..infrastructure..");

    @ArchTest ArchRule portsAreInterfaces = classes().that().haveSimpleNameEndingWith("Port")
        .should().beInterfaces();

    @ArchTest ArchRule noCycles = slices().matching("com.example.order.(*)..").should().beFreeOfCycles();
}
```
