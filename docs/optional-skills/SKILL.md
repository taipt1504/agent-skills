---
name: grpc-patterns
description: >
  gRPC patterns for Java Spring Boot applications. Covers proto file design, Spring Boot
  gRPC integration with grpc-spring-boot-starter, server and client implementation,
  reactive gRPC with reactor-grpc, error handling, interceptors, all streaming patterns,
  security (TLS/JWT), testing with InProcessServer, and Micrometer monitoring.
  Use when building gRPC services with Spring Boot 3.x and Java 17+.
---

# gRPC Patterns for Spring Boot

Production-ready gRPC patterns for Java 17+ / Spring Boot 3.x.

## Dependencies

```xml
<dependency>
    <groupId>net.devh</groupId>
    <artifactId>grpc-spring-boot-starter</artifactId>
    <version>3.1.0.RELEASE</version>
</dependency>
<dependency>
    <groupId>com.salesforce.servicelibs</groupId>
    <artifactId>reactor-grpc-stub</artifactId>
    <version>1.2.4</version>
</dependency>
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-testing</artifactId>
    <scope>test</scope>
</dependency>
```

## Proto Design Essentials

```protobuf
syntax = "proto3";
package com.example.order.v1;

option java_multiple_files = true;
option java_package = "com.example.order.v1";

service OrderService {
    rpc CreateOrder (CreateOrderRequest) returns (CreateOrderResponse);
    rpc GetOrder    (GetOrderRequest)    returns (OrderResponse);
    rpc ListOrders  (ListOrdersRequest)  returns (stream OrderResponse);  // server streaming
    rpc StreamOrders(stream OrderEvent)  returns (stream OrderResponse);  // bidirectional
}

message CreateOrderRequest {
    string customer_id = 1;
    repeated OrderItem items = 2;
    string idempotency_key = 3;  // always include for mutations
}

message CreateOrderResponse {
    string order_id = 1;
    OrderStatus status = 2;
    google.protobuf.Timestamp created_at = 3;
}

enum OrderStatus {
    ORDER_STATUS_UNSPECIFIED = 0;  // always define 0 as UNSPECIFIED
    ORDER_STATUS_CREATED = 1;
    ORDER_STATUS_CONFIRMED = 2;
    ORDER_STATUS_CANCELLED = 3;
}
```

## Server Implementation

```java
@GrpcService
@RequiredArgsConstructor
public class OrderGrpcService extends OrderServiceGrpc.OrderServiceImplBase {

    private final OrderService orderService;

    @Override
    public void createOrder(CreateOrderRequest request,
                            StreamObserver<CreateOrderResponse> responseObserver) {
        try {
            var command = toCommand(request);
            var result = orderService.create(command);
            responseObserver.onNext(toProto(result));
            responseObserver.onCompleted();
        } catch (ValidationException e) {
            responseObserver.onError(Status.INVALID_ARGUMENT
                .withDescription(e.getMessage()).asRuntimeException());
        } catch (NotFoundException e) {
            responseObserver.onError(Status.NOT_FOUND
                .withDescription(e.getMessage()).asRuntimeException());
        } catch (Exception e) {
            responseObserver.onError(Status.INTERNAL
                .withDescription("Internal error").asRuntimeException());
        }
    }

    @Override
    public void listOrders(ListOrdersRequest request,
                           StreamObserver<OrderResponse> responseObserver) {
        orderService.findByCustomer(request.getCustomerId())
            .forEach(order -> responseObserver.onNext(toProto(order)));
        responseObserver.onCompleted();
    }
}
```

## Client Implementation

```java
@Configuration
public class GrpcClientConfig {
    @Bean
    public OrderServiceGrpc.OrderServiceBlockingStub orderBlockingStub(
            @GrpcClient("order-service") ManagedChannel channel) {
        return OrderServiceGrpc.newBlockingStub(channel);
    }
}

// application.yml
// grpc.client.order-service.address=static://order-service:9090
// grpc.client.order-service.negotiation-type=plaintext
```

## Error Handling

```java
// Map domain exceptions to gRPC Status codes
private Status toStatus(Throwable e) {
    return switch (e) {
        case NotFoundException ex   -> Status.NOT_FOUND.withDescription(ex.getMessage());
        case ValidationException ex -> Status.INVALID_ARGUMENT.withDescription(ex.getMessage());
        case UnauthorizedException ex -> Status.UNAUTHENTICATED.withDescription(ex.getMessage());
        default -> Status.INTERNAL.withDescription("Internal server error");
        // ⚠️ Never expose internal details to client
    };
}
```

## Reactive gRPC (reactor-grpc)

```java
@GrpcService
public class ReactiveOrderService extends ReactorOrderServiceGrpc.OrderServiceImplBase {

    @Override
    public Mono<CreateOrderResponse> createOrder(Mono<CreateOrderRequest> request) {
        return request
            .map(req -> toCommand(req))
            .flatMap(orderService::create)
            .map(order -> CreateOrderResponse.newBuilder()
                .setOrderId(order.getId())
                .setStatus(OrderStatus.ORDER_STATUS_CREATED)
                .build());
    }

    @Override
    public Flux<OrderResponse> listOrders(Mono<ListOrdersRequest> request) {
        return request
            .flatMapMany(req -> orderService.findByCustomer(req.getCustomerId()))
            .map(this::toProto);
    }
}
```

## Interceptors

```java
// Server-side auth interceptor
@Component
public class AuthInterceptor implements ServerInterceptor {

    @Override
    public <R, S> ServerCall.Listener<R> interceptCall(
            ServerCall<R, S> call, Metadata headers, ServerCallHandler<R, S> next) {

        String token = headers.get(AUTHORIZATION_METADATA_KEY);
        if (!validateToken(token)) {
            call.close(Status.UNAUTHENTICATED.withDescription("Invalid token"), new Metadata());
            return new ServerCall.Listener<>() {};
        }

        Context ctx = Context.current().withValue(USER_ID_CTX_KEY, extractUserId(token));
        return Contexts.interceptCall(ctx, call, headers, next);
    }
}
```

## Testing

```java
@SpringBootTest
class OrderGrpcServiceTest {

    private static Server server;
    private static ManagedChannel channel;

    @BeforeAll
    static void setup() throws IOException {
        OrderGrpcService service = new OrderGrpcService(mockOrderService());
        server = InProcessServerBuilder.forName("test")
            .directExecutor().addService(service).build().start();
        channel = InProcessChannelBuilder.forName("test")
            .directExecutor().build();
    }

    @Test
    void shouldCreateOrder() {
        var stub = OrderServiceGrpc.newBlockingStub(channel);
        var request = CreateOrderRequest.newBuilder()
            .setCustomerId("customer-1")
            .addItems(OrderItem.newBuilder().setProductId("P1").setQuantity(2).build())
            .build();

        var response = stub.createOrder(request);
        assertThat(response.getStatus()).isEqualTo(OrderStatus.ORDER_STATUS_CREATED);
    }
}
```

## Configuration (application.yml)

```yaml
grpc:
  server:
    port: 9090
    security:
      certificateChain: classpath:tls/server.crt
      privateKey: classpath:tls/server.key
  client:
    order-service:
      address: static://order-service:9090
      negotiation-type: tls
      keepAliveTime: 30s
      keepAliveTimeout: 5s
```

## Status Code Mapping

| gRPC Status | HTTP Equivalent | Use When |
|-------------|----------------|----------|
| `OK` | 200 | Success |
| `INVALID_ARGUMENT` | 400 | Bad input |
| `UNAUTHENTICATED` | 401 | No/invalid auth |
| `PERMISSION_DENIED` | 403 | Forbidden |
| `NOT_FOUND` | 404 | Resource missing |
| `ALREADY_EXISTS` | 409 | Duplicate |
| `RESOURCE_EXHAUSTED` | 429 | Rate limited |
| `INTERNAL` | 500 | Server error (never expose details) |
| `UNAVAILABLE` | 503 | Downstream down |
| `DEADLINE_EXCEEDED` | 504 | Timeout |

## References

Load as needed:

- **[references/proto-streaming.md](references/proto-streaming.md)** — Full proto design rules, proto best practices (backward compatibility, field numbering), all 4 streaming patterns with examples
- **[references/reactive-advanced.md](references/reactive-advanced.md)** — Full reactor-grpc examples, deadline/timeout management, load balancing, health checks
- **[references/security-interceptors.md](references/security-interceptors.md)** — TLS setup, JWT auth interceptor with Context propagation, client-side interceptors (logging, metrics, retry)
- **[references/testing-monitoring.md](references/testing-monitoring.md)** — InProcessServer tests, mock stubs, Micrometer gRPC metrics, anti-patterns
