# gRPC Testing & Monitoring Reference

InProcessServer tests, mock stubs, Micrometer gRPC metrics, and anti-patterns.

## Table of Contents
- [InProcessServer Testing (Full Integration)](#inprocessserver-testing-full-integration)
- [Mock Stub Testing (Unit)](#mock-stub-testing-unit)
- [Reactive gRPC Testing](#reactive-grpc-testing)
- [Testing Interceptors](#testing-interceptors)
- [Micrometer gRPC Metrics](#micrometer-grpc-metrics)
- [Anti-Patterns](#anti-patterns)

---

## InProcessServer Testing (Full Integration)

Tests full gRPC pipeline (serialization, interceptors, etc.) without network.

```java
@SpringBootTest
class OrderGrpcServiceIntegrationTest {

    private static Server server;
    private static ManagedChannel channel;
    private static OrderServiceGrpc.OrderServiceBlockingStub stub;

    @BeforeAll
    static void startServer(@Autowired OrderGrpcService orderService,
                             @Autowired AuthInterceptor authInterceptor) throws IOException {
        server = InProcessServerBuilder.forName("test-order")
            .directExecutor()
            .addService(ServerInterceptors.intercept(orderService, authInterceptor))
            .build()
            .start();

        channel = InProcessChannelBuilder.forName("test-order")
            .directExecutor()
            .build();

        stub = OrderServiceGrpc.newBlockingStub(channel);
    }

    @AfterAll
    static void stopServer() throws InterruptedException {
        channel.shutdown().awaitTermination(5, TimeUnit.SECONDS);
        server.shutdown().awaitTermination(5, TimeUnit.SECONDS);
    }

    @Test
    void shouldCreateOrderSuccessfully() {
        var request = CreateOrderRequest.newBuilder()
            .setCustomerId("customer-1")
            .setIdempotencyKey(UUID.randomUUID().toString())
            .addItems(OrderItem.newBuilder()
                .setProductId("P1")
                .setQuantity(2)
                .setUnitPrice(1000)  // cents
                .build())
            .build();

        // Add auth metadata
        Metadata metadata = new Metadata();
        metadata.put(Metadata.Key.of("Authorization", Metadata.ASCII_STRING_MARSHALLER),
            "Bearer " + testToken);

        var response = stub.withInterceptors(MetadataUtils.newAttachHeadersInterceptor(metadata))
            .createOrder(request);

        assertThat(response.getOrderId()).isNotEmpty();
        assertThat(response.getStatus()).isEqualTo(OrderStatus.ORDER_STATUS_CREATED);
    }

    @Test
    void shouldReturnNotFoundForMissingOrder() {
        StatusRuntimeException exception = assertThrows(StatusRuntimeException.class, () ->
            stub.getOrder(GetOrderRequest.newBuilder().setOrderId("nonexistent").build()));
        assertThat(exception.getStatus().getCode()).isEqualTo(Status.Code.NOT_FOUND);
    }

    @Test
    void shouldStreamOrders() {
        var request = ListOrdersRequest.newBuilder()
            .setCustomerId("customer-1")
            .build();

        Iterator<OrderResponse> responses = stub.listOrders(request);
        List<OrderResponse> orders = new ArrayList<>();
        responses.forEachRemaining(orders::add);

        assertThat(orders).isNotEmpty();
    }
}
```

---

## Mock Stub Testing (Unit)

Fast unit tests mocking the gRPC stub directly.

```java
@ExtendWith(MockitoExtension.class)
class OrderGrpcClientTest {

    @Mock
    private OrderServiceGrpc.OrderServiceBlockingStub blockingStub;

    @InjectMocks
    private OrderGrpcClient orderGrpcClient;

    @Test
    void shouldCreateOrderViaGrpc() {
        var expectedResponse = CreateOrderResponse.newBuilder()
            .setOrderId("order-123")
            .setStatus(OrderStatus.ORDER_STATUS_CREATED)
            .build();

        when(blockingStub.withDeadlineAfter(anyLong(), any())).thenReturn(blockingStub);
        when(blockingStub.createOrder(any())).thenReturn(expectedResponse);

        var result = orderGrpcClient.createOrder(testRequest());

        assertThat(result.getOrderId()).isEqualTo("order-123");
    }

    @Test
    void shouldMapNotFoundToBusinessException() {
        when(blockingStub.withDeadlineAfter(anyLong(), any())).thenReturn(blockingStub);
        when(blockingStub.getOrder(any()))
            .thenThrow(Status.NOT_FOUND.withDescription("Order not found")
                .asRuntimeException());

        assertThatThrownBy(() -> orderGrpcClient.getOrder("order-999"))
            .isInstanceOf(NotFoundException.class)
            .hasMessageContaining("Order not found");
    }
}
```

---

## Reactive gRPC Testing

```java
@ExtendWith(MockitoExtension.class)
class ReactiveOrderServiceTest {

    @Mock
    private OrderService orderService;

    @InjectMocks
    private ReactiveOrderService reactiveOrderService;

    @Test
    void shouldCreateOrderReactively() {
        var order = Order.create(CustomerId.of("c-1"), testItems(), testAddress());
        when(orderService.create(any())).thenReturn(Mono.just(order));

        var request = CreateOrderRequest.newBuilder().setCustomerId("c-1").build();

        StepVerifier.create(reactiveOrderService.createOrder(Mono.just(request)))
            .expectNextMatches(r -> r.getStatus() == OrderStatus.ORDER_STATUS_CREATED)
            .verifyComplete();
    }

    @Test
    void shouldStreamOrdersReactively() {
        var orders = Flux.just(testOrder1(), testOrder2(), testOrder3());
        when(orderService.findByCustomer(any(), any())).thenReturn(orders);

        var request = ListOrdersRequest.newBuilder().setCustomerId("c-1").build();

        StepVerifier.create(reactiveOrderService.listOrders(Mono.just(request)))
            .expectNextCount(3)
            .verifyComplete();
    }

    @Test
    void shouldMapValidationExceptionToInvalidArgument() {
        when(orderService.create(any()))
            .thenReturn(Mono.error(new ValidationException("Invalid items")));

        var request = CreateOrderRequest.newBuilder().setCustomerId("c-1").build();

        StepVerifier.create(reactiveOrderService.createOrder(Mono.just(request)))
            .expectErrorMatches(ex -> ex instanceof StatusRuntimeException sre
                && sre.getStatus().getCode() == Status.Code.INVALID_ARGUMENT)
            .verify();
    }

    @Test
    void shouldProcessBidirectionalStream() {
        when(orderService.processEvent(any(), any()))
            .thenReturn(Mono.just(true));

        var events = Flux.just(
            OrderEvent.newBuilder().setOrderId("o-1").setType("CONFIRM").build(),
            OrderEvent.newBuilder().setOrderId("o-2").setType("SHIP").build()
        );

        StepVerifier.create(reactiveOrderService.processOrders(events))
            .expectNextMatches(ack -> ack.getOrderId().equals("o-1") && ack.getSuccess())
            .expectNextMatches(ack -> ack.getOrderId().equals("o-2") && ack.getSuccess())
            .verifyComplete();
    }
}
```

---

## Testing Interceptors

```java
@Test
void shouldRejectRequestWithoutToken() throws IOException {
    Server server = InProcessServerBuilder.forName("test-auth")
        .directExecutor()
        .addService(ServerInterceptors.intercept(new OrderGrpcService(mockService),
            new JwtAuthInterceptor(mockTokenService)))
        .build().start();

    ManagedChannel channel = InProcessChannelBuilder.forName("test-auth")
        .directExecutor().build();

    var stub = OrderServiceGrpc.newBlockingStub(channel);

    // No auth header — should fail
    StatusRuntimeException exception = assertThrows(StatusRuntimeException.class, () ->
        stub.createOrder(testRequest()));

    assertThat(exception.getStatus().getCode()).isEqualTo(Status.Code.UNAUTHENTICATED);

    channel.shutdown();
    server.shutdown();
}

@Test
void shouldAcceptRequestWithValidToken() throws Exception {
    when(mockTokenService.validate("valid-token"))
        .thenReturn(new JwtClaims("user-1", List.of("ORDER_CREATE")));

    Metadata metadata = new Metadata();
    metadata.put(Metadata.Key.of("Authorization", Metadata.ASCII_STRING_MARSHALLER),
        "Bearer valid-token");

    var response = stub.withInterceptors(MetadataUtils.newAttachHeadersInterceptor(metadata))
        .createOrder(testRequest());

    assertThat(response).isNotNull();
}
```

---

## Micrometer gRPC Metrics

```java
// Add dependency: net.devh:grpc-spring-boot-starter auto-configures Micrometer

// Metrics automatically exposed:
// - grpc_server_calls_seconds (histogram) — call duration
// - grpc_server_calls_total (counter) — by method, status
// - grpc_client_calls_seconds — client-side duration

@Configuration
public class GrpcMetricsConfig {

    // Custom metric: message size per method
    @Bean
    public ServerInterceptor messageMetricsInterceptor(MeterRegistry registry) {
        return new ServerInterceptor() {
            @Override
            public <R, S> ServerCall.Listener<R> interceptCall(
                    ServerCall<R, S> call, Metadata headers, ServerCallHandler<R, S> next) {
                String method = call.getMethodDescriptor().getBareMethodName();
                return new ForwardingServerCallListener.SimpleForwardingServerCallListener<>(
                        next.startCall(call, headers)) {
                    @Override
                    public void onMessage(R message) {
                        // Track message count
                        registry.counter("grpc.server.messages.received",
                            "method", method).increment();
                        super.onMessage(message);
                    }
                };
            }
        };
    }
}

// Prometheus scrape endpoint (Spring Boot Actuator)
// GET /actuator/prometheus → includes grpc_server_calls_seconds_bucket, etc.
```

---

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `block()` in reactive gRPC | Deadlock on gRPC thread pool | Use full reactive chain (`Mono/Flux`) |
| Exposing internal error details | Security risk — reveals stack traces, DB queries | Only expose user-safe messages via `Status.INTERNAL.withDescription("Internal error")` |
| Missing `onCompleted()` on server | Client hangs waiting | Always call `onCompleted()` or `onError()` |
| Ignoring deadline context | Downstream calls outlive parent deadline | Propagate `Context.current().getDeadline()` to all downstream |
| Large messages (> 4MB) | OOM, slow serialization | Stream large data with server streaming |
| No health check | Load balancers can't detect unhealthy pods | Always implement `grpc.health.v1.Health` |
| Reusing field numbers | Silent data corruption on schema change | Always `reserved` deleted field numbers |
| Missing idempotency key | Duplicate mutations on retry | Add `idempotency_key` to all mutation requests |
| Single connection shared across threads | Head-of-line blocking | One channel is fine (Netty multiplexes), but set concurrency limits |
| Not closing channels in tests | Resource leak, port conflicts | Use `@AfterAll` to `shutdown().awaitTermination()` |
