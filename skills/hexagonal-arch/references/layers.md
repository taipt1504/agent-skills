# Hexagonal Architecture Layers Reference

Complete domain, application, and infrastructure layer examples.

## Table of Contents
- [Domain Layer — Full Examples](#domain-layer--full-examples)
- [Application Layer — Full Use Case](#application-layer--full-use-case)
- [Infrastructure — Kafka Publisher](#infrastructure--kafka-publisher)
- [Infrastructure — External HTTP Adapter](#infrastructure--external-http-adapter)
- [Spring Wiring Configuration](#spring-wiring-configuration)

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
        Objects.requireNonNull(amount);
        Objects.requireNonNull(currency);
        if (amount.scale() > 2) throw new IllegalArgumentException("Scale must be <= 2");
    }

    public Money add(Money other) {
        requireSameCurrency(other);
        return new Money(amount.add(other.amount), currency);
    }

    public Money multiply(int quantity) {
        return new Money(amount.multiply(BigDecimal.valueOf(quantity)), currency);
    }

    public boolean isGreaterThan(Money other) {
        requireSameCurrency(other);
        return amount.compareTo(other.amount) > 0;
    }

    private void requireSameCurrency(Money other) {
        if (!currency.equals(other.currency))
            throw new IllegalArgumentException("Cannot operate on different currencies");
    }
}
```

### Aggregate Root — Full Implementation

```java
public class Order {
    private final OrderId id;
    private final CustomerId customerId;
    private final List<OrderItem> items;
    private final Address shippingAddress;
    private OrderStatus status;
    private Money totalAmount;
    private Instant createdAt;
    private Instant updatedAt;
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    // Factory method — only way to create
    public static Order create(CustomerId customerId, List<OrderItem> items, Address address) {
        if (items == null || items.isEmpty())
            throw new InvalidOrderException("Order must have at least one item");
        Order order = new Order(OrderId.generate(), customerId, List.copyOf(items),
            address, OrderStatus.CREATED, calculateTotal(items), Instant.now(), Instant.now());
        order.registerEvent(new OrderCreatedEvent(order.id, order.customerId, order.totalAmount, order.createdAt));
        return order;
    }

    // Reconstitution — for loading from DB (bypasses business validation)
    public static Order reconstitute(OrderId id, CustomerId customerId, List<OrderItem> items,
            Address address, OrderStatus status, Money totalAmount, Instant createdAt, Instant updatedAt) {
        return new Order(id, customerId, items, address, status, totalAmount, createdAt, updatedAt);
        // No events registered — this is loading, not a new action
    }

    private Order(OrderId id, CustomerId customerId, List<OrderItem> items, Address address,
                  OrderStatus status, Money totalAmount, Instant createdAt, Instant updatedAt) {
        this.id = Objects.requireNonNull(id);
        this.customerId = Objects.requireNonNull(customerId);
        this.items = items;
        this.shippingAddress = Objects.requireNonNull(address);
        this.status = status;
        this.totalAmount = totalAmount;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    // State transitions with business rules
    public void confirm() {
        if (status != OrderStatus.CREATED)
            throw new InvalidOrderException("Cannot confirm order in status: " + status);
        this.status = OrderStatus.CONFIRMED;
        this.updatedAt = Instant.now();
        registerEvent(new OrderConfirmedEvent(id, totalAmount));
    }

    public void cancel(String reason) {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED)
            throw new InvalidOrderException("Cannot cancel order in status: " + status);
        this.status = OrderStatus.CANCELLED;
        this.updatedAt = Instant.now();
        registerEvent(new OrderCancelledEvent(id, reason));
    }

    public void ship(String trackingNumber) {
        if (status != OrderStatus.CONFIRMED)
            throw new InvalidOrderException("Cannot ship order in status: " + status);
        this.status = OrderStatus.SHIPPED;
        this.updatedAt = Instant.now();
        registerEvent(new OrderShippedEvent(id, trackingNumber));
    }

    private static Money calculateTotal(List<OrderItem> items) {
        return items.stream().map(OrderItem::subtotal).reduce(Money.ZERO, Money::add);
    }

    private void registerEvent(DomainEvent event) { domainEvents.add(event); }
    public List<DomainEvent> getDomainEvents() { return List.copyOf(domainEvents); }
    public void clearDomainEvents() { domainEvents.clear(); }

    // Getters (no setters — state changes through business methods)
    public OrderId getId() { return id; }
    public CustomerId getCustomerId() { return customerId; }
    public OrderStatus getStatus() { return status; }
    public Money getTotalAmount() { return totalAmount; }
    public Instant getCreatedAt() { return createdAt; }
    public List<OrderItem> getItems() { return List.copyOf(items); }
}
```

### Domain Events

```java
public interface DomainEvent { Instant occurredAt(); }

public record OrderCreatedEvent(OrderId orderId, CustomerId customerId,
        Money totalAmount, Instant occurredAt) implements DomainEvent {}

public record OrderConfirmedEvent(OrderId orderId, Money totalAmount, Instant occurredAt)
        implements DomainEvent {
    public OrderConfirmedEvent(OrderId orderId, Money totalAmount) {
        this(orderId, totalAmount, Instant.now());
    }
}

public record OrderCancelledEvent(OrderId orderId, String reason, Instant occurredAt)
        implements DomainEvent {
    public OrderCancelledEvent(OrderId orderId, String reason) {
        this(orderId, reason, Instant.now());
    }
}
```

---

## Application Layer — Full Use Case

```java
@Service @RequiredArgsConstructor @Slf4j
public class CreateOrderService implements CreateOrderUseCase {
    private final OrderPersistencePort orderPersistence;
    private final PaymentPort paymentPort;
    private final OrderEventPublisherPort eventPublisher;
    private final NotificationPort notificationPort;

    @Override
    public Mono<OrderResponse> createOrder(CreateOrderCommand cmd) {
        // 1. Map command to domain objects
        var customerId = CustomerId.of(cmd.customerId());
        var items = cmd.items().stream()
            .map(i -> new OrderItem(ProductId.of(i.productId()), i.quantity(),
                new Money(i.price(), "USD")))
            .toList();
        var address = new Address(cmd.shippingAddress().street(), cmd.shippingAddress().city(),
            cmd.shippingAddress().zipCode(), cmd.shippingAddress().country());

        // 2. Create domain object (business rules validated inside)
        Order order = Order.create(customerId, items, address);

        // 3. Orchestrate
        return orderPersistence.save(order)
            .flatMap(saved -> paymentPort.processPayment(saved.getId(), saved.getTotalAmount(), customerId)
                .flatMap(result -> {
                    if (result.isSuccessful()) saved.confirm();
                    else saved.cancel("Payment failed: " + result.failureReason());
                    return orderPersistence.save(saved);
                }))
            .flatMap(finalOrder -> {
                var events = finalOrder.getDomainEvents();
                finalOrder.clearDomainEvents();
                return eventPublisher.publishEvents(events).thenReturn(finalOrder);
            })
            .doOnSuccess(o -> {
                if (o.getStatus() == OrderStatus.CONFIRMED)
                    notificationPort.sendOrderConfirmation(o.getId(), o.getCustomerId())
                        .subscribe(null, ex -> log.error("Notification failed", ex));
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
        String topic = resolveTopic(event);
        String key = resolveKey(event);
        return Mono.fromFuture(kafkaTemplate.send(topic, key, event))
            .doOnSuccess(r -> log.debug("Published {} to {}", event.getClass().getSimpleName(), topic))
            .doOnError(e -> log.error("Failed to publish {}", event, e))
            .then();
    }

    private String resolveTopic(DomainEvent event) {
        return switch (event) {
            case OrderCreatedEvent e -> "order.created";
            case OrderConfirmedEvent e -> "order.confirmed";
            case OrderCancelledEvent e -> "order.cancelled";
            default -> "order.events";
        };
    }

    private String resolveKey(DomainEvent event) {
        return switch (event) {
            case OrderCreatedEvent e -> e.orderId().value();
            case OrderConfirmedEvent e -> e.orderId().value();
            case OrderCancelledEvent e -> e.orderId().value();
            default -> UUID.randomUUID().toString();
        };
    }
}
```

---

## Infrastructure — External HTTP Adapter

```java
@Component @RequiredArgsConstructor @Slf4j
public class PaymentApiAdapter implements PaymentPort {
    private final WebClient paymentWebClient;

    @Override
    public Mono<PaymentResult> processPayment(OrderId orderId, Money amount, CustomerId customerId) {
        var request = new PaymentRequest(orderId.value(), customerId.value(),
            amount.amount(), amount.currency());

        return paymentWebClient.post()
            .uri("/api/payments")
            .bodyValue(request)
            .retrieve()
            .bodyToMono(PaymentApiResponse.class)
            .map(r -> new PaymentResult(r.isSuccess(), r.transactionId(), r.failureReason()))
            .onErrorResume(WebClientResponseException.class,
                e -> Mono.just(PaymentResult.failed("Payment API error: " + e.getStatusCode())))
            .timeout(Duration.ofSeconds(10))
            .onErrorResume(TimeoutException.class,
                e -> Mono.just(PaymentResult.failed("Payment API timeout")));
    }
}
```

---

## Spring Wiring Configuration

```java
@Configuration
public class BeanConfig {
    // Spring auto-wires when @Component/@Service is used on adapters.
    // This bean config is only needed for explicit construction or non-annotated adapters.

    @Bean
    public WebClient paymentWebClient() {
        return WebClient.builder()
            .baseUrl("http://payment-service:8080")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .codecs(c -> c.defaultCodecs().maxInMemorySize(1024 * 1024))
            .build();
    }
}

// Input adapter wiring
// PortInterface → concrete @Service is automatically injected by Spring via constructor injection
// No manual wiring needed when using @Component + @Service + constructor injection
```
