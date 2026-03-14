# Mapping & Testing Reference

MapStruct mappers, reconstitution patterns, and testing by layer.

## Table of Contents
- [MapStruct REST Mapper](#mapstruct-rest-mapper)
- [MapStruct Persistence Mapper](#mapstruct-persistence-mapper)
- [Reconstitution Pattern (DB to Domain)](#reconstitution-pattern-db-to-domain)
- [Domain Unit Tests](#domain-unit-tests)
- [Application Layer Tests (Mocked Ports)](#application-layer-tests-mocked-ports)
- [Infrastructure Integration Tests](#infrastructure-integration-tests)
- [ArchUnit Layer Enforcement](#archunit-layer-enforcement)

---

## MapStruct REST Mapper

```java
// Request → Command (Input adapter)
@Mapper(componentModel = "spring")
public interface OrderRestMapper {

    // CreateOrderRequest → CreateOrderCommand
    @Mapping(target = "items", source = "items")
    CreateOrderCommand toCommand(CreateOrderRequest request);

    @Mapping(target = "price", source = "price")
    CreateOrderCommand.Item toCommandItem(CreateOrderRequest.Item item);

    // Order → OrderResponse (output)
    @Mapping(target = "orderId", source = "id.value")
    @Mapping(target = "customerId", source = "customerId.value")
    @Mapping(target = "status", source = "status")
    @Mapping(target = "totalAmount", source = "totalAmount.amount")
    @Mapping(target = "currency", source = "totalAmount.currency")
    OrderResponse toResponse(Order order);

    // Flux of Order — MapStruct doesn't handle reactive, map manually
    default Flux<OrderResponse> toResponseFlux(Flux<Order> orders) {
        return orders.map(this::toResponse);
    }
}
```

---

## MapStruct Persistence Mapper

```java
// Domain ↔ JPA Entity
@Mapper(componentModel = "spring")
public interface OrderPersistenceMapper {

    // Domain → Entity (for save)
    @Mapping(target = "id", source = "id.value")
    @Mapping(target = "customerId", source = "customerId.value")
    @Mapping(target = "status", source = "status")
    @Mapping(target = "totalAmount", source = "totalAmount.amount")
    @Mapping(target = "currency", source = "totalAmount.currency")
    @Mapping(target = "items", source = "items")
    OrderEntity toEntity(Order order);

    @Mapping(target = "productId", source = "productId.value")
    @Mapping(target = "unitPrice", source = "unitPrice.amount")
    OrderItemEntity toItemEntity(OrderItem item);

    // Entity → Domain (for load) — use domain reconstitute factory
    default Order toDomain(OrderEntity entity) {
        return Order.reconstitute(
            OrderId.of(entity.getId()),
            CustomerId.of(entity.getCustomerId()),
            entity.getItems().stream().map(this::toItemDomain).toList(),
            toAddressDomain(entity),
            OrderStatus.valueOf(entity.getStatus()),
            new Money(entity.getTotalAmount(), entity.getCurrency()),
            entity.getCreatedAt(),
            entity.getUpdatedAt()
        );
    }

    OrderItem toItemDomain(OrderItemEntity entity);
}
```

---

## Reconstitution Pattern (DB to Domain)

Reconstitution bypasses business validation — it restores existing state, not creates new.

```java
// Repository adapter (infrastructure)
@Repository @RequiredArgsConstructor
public class OrderJpaAdapter implements OrderPersistencePort {
    private final OrderJpaRepository jpaRepository;
    private final OrderPersistenceMapper mapper;

    @Override
    public Mono<Order> findById(OrderId orderId) {
        return Mono.justOrEmpty(jpaRepository.findById(orderId.value()))
            .map(mapper::toDomain)  // uses reconstitute internally
            .switchIfEmpty(Mono.error(new NotFoundException("Order not found: " + orderId.value())));
    }

    @Override
    public Mono<Order> save(Order order) {
        OrderEntity entity = mapper.toEntity(order);
        return Mono.fromCallable(() -> jpaRepository.save(entity))
            .subscribeOn(Schedulers.boundedElastic())
            .map(mapper::toDomain);
    }
}

// R2DBC version
@Repository @RequiredArgsConstructor
public class OrderR2dbcAdapter implements OrderPersistencePort {
    private final OrderR2dbcRepository r2dbcRepository;
    private final OrderPersistenceMapper mapper;

    @Override
    public Mono<Order> save(Order order) {
        return r2dbcRepository.save(mapper.toEntity(order))
            .map(mapper::toDomain);
    }
}
```

---

## Domain Unit Tests

No Spring context — pure POJO tests. Fast.

```java
class OrderTest {

    @Test
    void shouldCreateOrderWithValidItems() {
        var customerId = CustomerId.of("customer-1");
        var items = List.of(new OrderItem(ProductId.of("P1"), 2, new Money(new BigDecimal("10.00"), "USD")));
        var address = new Address("123 Main St", "Springfield", "62701", "US");

        var order = Order.create(customerId, items, address);

        assertThat(order.getId()).isNotNull();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CREATED);
        assertThat(order.getTotalAmount()).isEqualTo(new Money(new BigDecimal("20.00"), "USD"));
        assertThat(order.getDomainEvents()).hasSize(1)
            .first().isInstanceOf(OrderCreatedEvent.class);
    }

    @Test
    void shouldRejectEmptyItems() {
        assertThatThrownBy(() ->
            Order.create(CustomerId.of("customer-1"), List.of(), someAddress()))
            .isInstanceOf(InvalidOrderException.class)
            .hasMessage("Order must have at least one item");
    }

    @Test
    void shouldConfirmCreatedOrder() {
        var order = createTestOrder();

        order.confirm();

        assertThat(order.getStatus()).isEqualTo(OrderStatus.CONFIRMED);
        assertThat(order.getDomainEvents()).anyMatch(e -> e instanceof OrderConfirmedEvent);
    }

    @Test
    void shouldNotConfirmAlreadyConfirmedOrder() {
        var order = createTestOrder();
        order.confirm();

        assertThatThrownBy(order::confirm)
            .isInstanceOf(InvalidOrderException.class)
            .hasMessageContaining("Cannot confirm order in status: CONFIRMED");
    }

    @Test
    void shouldNotCancelShippedOrder() {
        var order = createTestOrder();
        order.confirm();
        order.ship("TRACK-123");

        assertThatThrownBy(() -> order.cancel("changed mind"))
            .isInstanceOf(InvalidOrderException.class);
    }

    private Order createTestOrder() {
        return Order.create(
            CustomerId.of("customer-1"),
            List.of(new OrderItem(ProductId.of("P1"), 1, new Money(new BigDecimal("50.00"), "USD"))),
            someAddress());
    }
}
```

---

## Application Layer Tests (Mocked Ports)

Mock all ports — test orchestration logic only, not infrastructure.

```java
@ExtendWith(MockitoExtension.class)
class CreateOrderServiceTest {

    @Mock private OrderPersistencePort orderPersistence;
    @Mock private PaymentPort paymentPort;
    @Mock private OrderEventPublisherPort eventPublisher;
    @Mock private NotificationPort notificationPort;

    @InjectMocks
    private CreateOrderService createOrderService;

    @Test
    void shouldCreateAndConfirmOrderOnSuccessfulPayment() {
        // Arrange
        var command = validCreateOrderCommand();
        when(orderPersistence.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(paymentPort.processPayment(any(), any(), any()))
            .thenReturn(Mono.just(PaymentResult.success("tx-123")));
        when(eventPublisher.publishEvents(anyList())).thenReturn(Mono.empty());
        when(notificationPort.sendOrderConfirmation(any(), any())).thenReturn(Mono.empty());

        // Act & Assert
        StepVerifier.create(createOrderService.createOrder(command))
            .expectNextMatches(response -> response.status() == OrderStatus.CONFIRMED)
            .verifyComplete();

        verify(orderPersistence, times(2)).save(any());  // initial save + after payment
        verify(eventPublisher).publishEvents(argThat(events ->
            events.stream().anyMatch(e -> e instanceof OrderConfirmedEvent)));
    }

    @Test
    void shouldCancelOrderOnPaymentFailure() {
        var command = validCreateOrderCommand();
        when(orderPersistence.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
        when(paymentPort.processPayment(any(), any(), any()))
            .thenReturn(Mono.just(PaymentResult.failed("Insufficient funds")));
        when(eventPublisher.publishEvents(anyList())).thenReturn(Mono.empty());

        StepVerifier.create(createOrderService.createOrder(command))
            .expectNextMatches(response -> response.status() == OrderStatus.CANCELLED)
            .verifyComplete();

        verify(eventPublisher).publishEvents(argThat(events ->
            events.stream().anyMatch(e -> e instanceof OrderCancelledEvent)));
    }
}
```

---

## Infrastructure Integration Tests

Test adapter + real DB (Testcontainers). No domain logic — only persistence correctness.

```java
@DataR2dbcTest
@Testcontainers
class OrderR2dbcAdapterTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:postgresql://" + postgres.getHost() + ":" + postgres.getMappedPort(5432) + "/test");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
    }

    @Autowired
    private OrderR2dbcAdapter adapter;

    @Test
    void shouldSaveAndFindOrder() {
        var order = Order.create(
            CustomerId.of("customer-1"),
            List.of(new OrderItem(ProductId.of("P1"), 1, Money.of(50, "USD"))),
            testAddress());

        StepVerifier.create(adapter.save(order)
            .flatMap(saved -> adapter.findById(saved.getId())))
            .expectNextMatches(found -> found.getStatus() == OrderStatus.CREATED)
            .verifyComplete();
    }
}
```

---

## ArchUnit Layer Enforcement

```java
@AnalyzeClasses(packages = "com.example.order")
class ArchitectureTest {

    @ArchTest
    ArchRule domainDoesNotDependOnInfrastructure = noClasses()
        .that().resideInAPackage("..domain..")
        .should().dependOnClassesThat()
        .resideInAnyPackage("..infrastructure..", "..adapter..");

    @ArchTest
    ArchRule applicationOnlyDependsOnDomain = classes()
        .that().resideInAPackage("..application..")
        .should().onlyDependOnClassesThat()
        .resideInAnyPackage("..domain..", "..application..",
            "java..", "org.springframework..", "reactor..", "lombok..");

    @ArchTest
    ArchRule portsAreInterfaces = classes()
        .that().haveSimpleNameEndingWith("Port")
        .should().beInterfaces();

    @ArchTest
    ArchRule useCasesAreInterfaces = classes()
        .that().haveSimpleNameEndingWith("UseCase")
        .should().beInterfaces();

    @ArchTest
    ArchRule noCircularDependencies = slices()
        .matching("com.example.order.(*)..").should().beFreeOfCycles();
}
```
