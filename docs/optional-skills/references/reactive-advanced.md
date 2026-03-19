# Reactive gRPC, Deadlines & Load Balancing Reference

Full reactor-grpc patterns, deadline management, load balancing, and health checks.

## Table of Contents
- [Full Reactive Server](#full-reactive-server)
- [Reactive Client](#reactive-client)
- [Deadline & Timeout Management](#deadline--timeout-management)
- [Load Balancing](#load-balancing)
- [Health Checks](#health-checks)
- [Retry Policy](#retry-policy)
- [Interceptor Chaining](#interceptor-chaining)

---

## Full Reactive Server

```java
@GrpcService
@RequiredArgsConstructor
public class ReactiveOrderService extends ReactorOrderServiceGrpc.OrderServiceImplBase {
    private final OrderService orderService;

    // Unary — Mono in, Mono out
    @Override
    public Mono<CreateOrderResponse> createOrder(Mono<CreateOrderRequest> request) {
        return request
            .map(this::toCommand)
            .flatMap(orderService::create)
            .map(order -> CreateOrderResponse.newBuilder()
                .setOrderId(order.getId().value())
                .setStatus(OrderStatus.ORDER_STATUS_CREATED)
                .setCreatedAt(toTimestamp(order.getCreatedAt()))
                .build())
            .onErrorMap(ValidationException.class, ex ->
                Status.INVALID_ARGUMENT.withDescription(ex.getMessage()).asRuntimeException())
            .onErrorMap(NotFoundException.class, ex ->
                Status.NOT_FOUND.withDescription(ex.getMessage()).asRuntimeException());
    }

    // Server streaming — Mono in, Flux out
    @Override
    public Flux<OrderResponse> listOrders(Mono<ListOrdersRequest> request) {
        return request
            .flatMapMany(req -> orderService.findByCustomer(req.getCustomerId(),
                PageRequest.of(req.getPage(), req.getSize())))
            .map(this::toProto)
            .onErrorMap(ex -> Status.INTERNAL.withDescription("List failed").asRuntimeException());
    }

    // Client streaming — Flux in, Mono out
    @Override
    public Mono<BatchCreateResponse> batchCreate(Flux<CreateOrderRequest> requests) {
        return requests
            .map(this::toCommand)
            .flatMap(orderService::create)
            .count()
            .map(count -> BatchCreateResponse.newBuilder()
                .setCreatedCount(count.intValue())
                .build());
    }

    // Bidirectional — Flux in, Flux out
    @Override
    public Flux<OrderAck> processOrders(Flux<OrderEvent> events) {
        return events
            .flatMap(event -> orderService.processEvent(event.getOrderId(), event.getType())
                .map(success -> OrderAck.newBuilder()
                    .setOrderId(event.getOrderId())
                    .setSuccess(success)
                    .build())
                .onErrorReturn(OrderAck.newBuilder()
                    .setOrderId(event.getOrderId())
                    .setSuccess(false)
                    .build()), 8);  // max 8 concurrent
    }

    private CreateOrderCommand toCommand(CreateOrderRequest req) {
        return new CreateOrderCommand(req.getCustomerId(), req.getIdempotencyKey(),
            req.getItemsList().stream()
                .map(i -> new CreateOrderCommand.Item(i.getProductId(), i.getQuantity()))
                .toList());
    }

    private OrderResponse toProto(Order order) {
        return OrderResponse.newBuilder()
            .setOrderId(order.getId().value())
            .setStatus(order.getStatus().name())
            .build();
    }
}
```

---

## Reactive Client

```java
@Configuration
public class ReactiveGrpcClientConfig {
    @Bean
    public ReactorOrderServiceGrpc.ReactorOrderServiceStub orderReactiveStub(
            @GrpcClient("order-service") ManagedChannel channel) {
        return ReactorOrderServiceGrpc.newReactorStub(channel);
    }
}

@Service @RequiredArgsConstructor
public class OrderGrpcClient {
    private final ReactorOrderServiceGrpc.ReactorOrderServiceStub orderStub;

    // Unary call
    public Mono<CreateOrderResponse> createOrder(CreateOrderRequest request) {
        return orderStub.withDeadlineAfter(5, TimeUnit.SECONDS)
            .createOrder(request)
            .onErrorMap(StatusRuntimeException.class, this::toBusinessException);
    }

    // Server streaming
    public Flux<OrderResponse> listOrders(String customerId) {
        return orderStub.withDeadlineAfter(30, TimeUnit.SECONDS)
            .listOrders(ListOrdersRequest.newBuilder()
                .setCustomerId(customerId)
                .setPage(0).setSize(100)
                .build())
            .retryWhen(Retry.backoff(3, Duration.ofMillis(500))
                .filter(ex -> ex instanceof StatusRuntimeException ste
                    && ste.getStatus().getCode() == Status.Code.UNAVAILABLE));
    }

    // Client streaming
    public Mono<BatchCreateResponse> batchCreate(List<CreateOrderRequest> requests) {
        return orderStub.batchCreate(Flux.fromIterable(requests));
    }

    // Bidirectional
    public Flux<OrderAck> processEvents(Flux<OrderEvent> events) {
        return orderStub.processOrders(events);
    }

    private Throwable toBusinessException(StatusRuntimeException e) {
        return switch (e.getStatus().getCode()) {
            case NOT_FOUND -> new NotFoundException(e.getStatus().getDescription());
            case INVALID_ARGUMENT -> new ValidationException(e.getStatus().getDescription());
            case UNAUTHENTICATED -> new UnauthorizedException(e.getStatus().getDescription());
            default -> new ServiceUnavailableException("gRPC call failed: " + e.getStatus());
        };
    }
}
```

---

## Deadline & Timeout Management

```java
// Client-side deadline (use withDeadlineAfter, not withDeadline)
stub.withDeadlineAfter(5, TimeUnit.SECONDS).createOrder(request);

// Propagate parent deadline to nested calls
@Override
public Mono<CreateOrderResponse> createOrder(Mono<CreateOrderRequest> request) {
    Context ctx = Context.current();  // contains incoming deadline
    return request.flatMap(req ->
        Mono.defer(() -> {
            // All downstream calls inherit the deadline
            return inventoryClient.withDeadline(ctx.getDeadline())
                .checkStock(req.getItemsList());
        }));
}

// Default deadlines via client interceptor
public class DefaultDeadlineInterceptor implements ClientInterceptor {
    private static final long DEFAULT_DEADLINE_SECONDS = 10;

    @Override
    public <R, S> ClientCall<R, S> interceptCall(
            MethodDescriptor<R, S> method, CallOptions opts, Channel next) {
        if (opts.getDeadline() == null) {
            opts = opts.withDeadlineAfter(DEFAULT_DEADLINE_SECONDS, TimeUnit.SECONDS);
        }
        return next.newCall(method, opts);
    }
}
```

---

## Load Balancing

```java
// Round-robin across multiple servers (client-side LB)
ManagedChannel channel = ManagedChannelBuilder
    .forTarget("dns:///order-service.production.svc.cluster.local:9090")
    .defaultLoadBalancingPolicy("round_robin")
    .build();

// With service discovery (via resolver factory)
ManagedChannel channel = ManagedChannelBuilder
    .forTarget("consul://order-service/grpc")
    .defaultLoadBalancingPolicy("round_robin")
    .build();

// application.yml — multiple static addresses
grpc:
  client:
    order-service:
      address: "static://order-1:9090,order-2:9090,order-3:9090"
      default-load-balancing-policy: round_robin
      negotiation-type: plaintext

# Kubernetes service (DNS resolves to pod IPs)
grpc:
  client:
    order-service:
      address: "dns:///order-service.default.svc.cluster.local:9090"
      default-load-balancing-policy: round_robin
```

---

## Health Checks

```java
// Server — implement gRPC standard health check
@Configuration
public class GrpcHealthConfig {
    @Bean
    public HealthStatusManager healthStatusManager() {
        return new HealthStatusManager();
    }

    @Bean
    public HealthGrpc.HealthImplBase healthService(HealthStatusManager manager) {
        return manager.getHealthService();
    }
}

// Update health status based on app state
@Component @RequiredArgsConstructor
public class OrderServiceHealthUpdater {
    private final HealthStatusManager healthStatusManager;

    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        healthStatusManager.setStatus("order-service", HealthCheckResponse.ServingStatus.SERVING);
    }

    @EventListener(ContextClosedEvent.class)
    public void onShutdown() {
        healthStatusManager.setStatus("order-service", HealthCheckResponse.ServingStatus.NOT_SERVING);
    }

    public void setUnhealthy(String reason) {
        log.warn("Setting service to NOT_SERVING: {}", reason);
        healthStatusManager.setStatus("order-service", HealthCheckResponse.ServingStatus.NOT_SERVING);
    }
}

// Client health check
@Bean
public HealthGrpc.HealthBlockingStub healthStub(@GrpcClient("order-service") ManagedChannel ch) {
    return HealthGrpc.newBlockingStub(ch);
}

// Health check indicator
@Component @RequiredArgsConstructor
public class OrderGrpcHealthIndicator implements HealthIndicator {
    private final HealthGrpc.HealthBlockingStub healthStub;

    @Override
    public Health health() {
        try {
            var response = healthStub.withDeadlineAfter(2, TimeUnit.SECONDS)
                .check(HealthCheckRequest.newBuilder().setService("order-service").build());
            if (response.getStatus() == HealthCheckResponse.ServingStatus.SERVING)
                return Health.up().build();
            return Health.down().withDetail("status", response.getStatus()).build();
        } catch (Exception e) {
            return Health.down(e).build();
        }
    }
}
```

---

## Retry Policy

```yaml
# application.yml — gRPC client retry (server must be idempotent)
grpc:
  client:
    order-service:
      address: "dns:///order-service:9090"
      service-config: |
        {
          "methodConfig": [{
            "name": [{"service": "com.example.order.v1.OrderService", "method": "GetOrder"}],
            "retryPolicy": {
              "maxAttempts": 3,
              "initialBackoff": "0.5s",
              "maxBackoff": "10s",
              "backoffMultiplier": 2,
              "retryableStatusCodes": ["UNAVAILABLE", "RESOURCE_EXHAUSTED"]
            }
          }]
        }
```

```java
// Programmatic retry in reactive client
public Mono<OrderResponse> getOrderWithRetry(String orderId) {
    return orderStub.getOrder(GetOrderRequest.newBuilder().setOrderId(orderId).build())
        .retryWhen(Retry.backoff(3, Duration.ofMillis(500))
            .filter(ex -> ex instanceof StatusRuntimeException sre
                && (sre.getStatus().getCode() == Status.Code.UNAVAILABLE
                    || sre.getStatus().getCode() == Status.Code.RESOURCE_EXHAUSTED))
            .doBeforeRetry(signal -> log.warn("Retry #{}", signal.totalRetries() + 1)));
}
```

---

## Interceptor Chaining

```java
// Register multiple interceptors on server
@Configuration
public class GrpcServerConfig {
    @Bean
    public GlobalServerInterceptorConfigurer interceptorConfigurer(
            AuthInterceptor authInterceptor,
            LoggingInterceptor loggingInterceptor,
            MetricsInterceptor metricsInterceptor) {
        return registry -> {
            registry.add(metricsInterceptor);  // outermost — timing everything
            registry.add(loggingInterceptor);
            registry.add(authInterceptor);      // innermost — auth first
        };
    }
}

// Or on individual service
@GrpcService(interceptors = {AuthInterceptor.class, LoggingInterceptor.class})
public class OrderGrpcService extends OrderServiceGrpc.OrderServiceImplBase { ... }
```
