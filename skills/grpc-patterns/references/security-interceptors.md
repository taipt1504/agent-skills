# gRPC Security & Interceptors Reference

TLS setup, JWT auth interceptor, context propagation, and client-side interceptors.

## Table of Contents
- [TLS Configuration](#tls-configuration)
- [Mutual TLS (mTLS)](#mutual-tls-mtls)
- [JWT Auth Server Interceptor](#jwt-auth-server-interceptor)
- [Context Propagation](#context-propagation)
- [Client-Side Auth Interceptor](#client-side-auth-interceptor)
- [Logging Interceptor](#logging-interceptor)
- [Metrics Interceptor](#metrics-interceptor)
- [Retry Interceptor (Client)](#retry-interceptor-client)

---

## TLS Configuration

```yaml
# Server — application.yml
grpc:
  server:
    port: 9090
    security:
      certificate-chain: classpath:tls/server.crt
      private-key: classpath:tls/server.key

# Client
grpc:
  client:
    order-service:
      address: "static://order-service:9090"
      negotiation-type: tls
      security:
        trust-cert-collection: classpath:tls/ca.crt  # optional — for self-signed CA
      keepAliveTime: 30s
      keepAliveTimeout: 5s
      keepAliveWithoutCalls: false
```

```java
// Custom TLS config (when not using auto-config)
@Bean
public GrpcChannelFactory grpcChannelFactory(GrpcChannelProperties channelProperties) {
    return NettyChannelBuilderOption.forAddress(...)
        .useTransportSecurity()
        .sslContext(GrpcSslContexts.forClient()
            .trustManager(new File("ca.crt"))
            .build());
}
```

---

## Mutual TLS (mTLS)

Both server and client authenticate with certificates.

```yaml
# Server
grpc:
  server:
    security:
      certificate-chain: classpath:tls/server.crt
      private-key: classpath:tls/server.key
      client-auth: REQUIRE  # NONE, OPTIONAL, REQUIRE
      trust-cert-collection: classpath:tls/ca.crt  # for verifying client certs

# Client
grpc:
  client:
    order-service:
      negotiation-type: tls
      security:
        certificate-chain: classpath:tls/client.crt
        private-key: classpath:tls/client.key
        trust-cert-collection: classpath:tls/ca.crt
```

---

## JWT Auth Server Interceptor

```java
@Component
public class JwtAuthInterceptor implements ServerInterceptor {

    // Context key for propagating user ID
    static final Context.Key<String> USER_ID = Context.key("userId");
    static final Context.Key<List<String>> USER_ROLES = Context.key("userRoles");

    private static final Metadata.Key<String> AUTHORIZATION_KEY =
        Metadata.Key.of("Authorization", Metadata.ASCII_STRING_MARSHALLER);

    private final JwtTokenService tokenService;

    @Override
    public <R, S> ServerCall.Listener<R> interceptCall(
            ServerCall<R, S> call, Metadata headers, ServerCallHandler<R, S> next) {

        String token = headers.get(AUTHORIZATION_KEY);

        // Allow public methods (health check, etc.)
        if (isPublicMethod(call.getMethodDescriptor())) {
            return next.startCall(call, headers);
        }

        if (token == null || !token.startsWith("Bearer ")) {
            call.close(Status.UNAUTHENTICATED
                .withDescription("Missing or invalid Authorization header"), new Metadata());
            return new ServerCall.Listener<>() {};
        }

        try {
            JwtClaims claims = tokenService.validate(token.substring(7));
            Context ctx = Context.current()
                .withValue(USER_ID, claims.getSubject())
                .withValue(USER_ROLES, claims.getRoles());
            return Contexts.interceptCall(ctx, call, headers, next);
        } catch (JwtValidationException e) {
            call.close(Status.UNAUTHENTICATED.withDescription("Invalid token: " + e.getMessage()),
                new Metadata());
            return new ServerCall.Listener<>() {};
        }
    }

    private boolean isPublicMethod(MethodDescriptor<?, ?> method) {
        return method.getFullMethodName().contains("grpc.health.v1.Health");
    }
}
```

---

## Context Propagation

```java
// Read user ID from context in service implementation
@GrpcService
public class OrderGrpcService extends OrderServiceGrpc.OrderServiceImplBase {

    @Override
    public void createOrder(CreateOrderRequest request,
                            StreamObserver<CreateOrderResponse> responseObserver) {
        // Access authenticated user from context
        String userId = JwtAuthInterceptor.USER_ID.get();
        List<String> roles = JwtAuthInterceptor.USER_ROLES.get();

        if (userId == null) {
            responseObserver.onError(Status.UNAUTHENTICATED
                .withDescription("Not authenticated").asRuntimeException());
            return;
        }

        // Verify authorization
        if (!roles.contains("ORDER_CREATE")) {
            responseObserver.onError(Status.PERMISSION_DENIED
                .withDescription("Insufficient permissions").asRuntimeException());
            return;
        }

        // Proceed with user context
        var command = toCommand(request, userId);
        var order = orderService.create(command);
        responseObserver.onNext(toProto(order));
        responseObserver.onCompleted();
    }
}

// Reactive — Context propagation with reactor-grpc
@GrpcService
public class ReactiveOrderService extends ReactorOrderServiceGrpc.OrderServiceImplBase {

    @Override
    public Mono<CreateOrderResponse> createOrder(Mono<CreateOrderRequest> request) {
        return Mono.deferContextual(ctx -> {
            String userId = JwtAuthInterceptor.USER_ID.get();  // gRPC Context, not Reactor
            return request.map(req -> toCommand(req, userId))
                .flatMap(orderService::create)
                .map(this::toProto);
        });
    }
}
```

---

## Client-Side Auth Interceptor

```java
@Component
public class ClientAuthInterceptor implements ClientInterceptor {
    private static final Metadata.Key<String> AUTHORIZATION_KEY =
        Metadata.Key.of("Authorization", Metadata.ASCII_STRING_MARSHALLER);

    private final TokenProvider tokenProvider;

    @Override
    public <R, S> ClientCall<R, S> interceptCall(
            MethodDescriptor<R, S> method, CallOptions options, Channel next) {

        return new ForwardingClientCall.SimpleForwardingClientCall<>(
                next.newCall(method, options)) {
            @Override
            public void start(Listener<S> responseListener, Metadata headers) {
                String token = tokenProvider.getToken();  // may refresh if expired
                headers.put(AUTHORIZATION_KEY, "Bearer " + token);
                super.start(responseListener, headers);
            }
        };
    }
}

// Register on channel
@Bean
public ManagedChannel orderChannel(@GrpcClient("order-service") ChannelProperties props,
                                    ClientAuthInterceptor authInterceptor) {
    return ManagedChannelBuilder
        .forAddress(props.getAddress(), props.getPort())
        .intercept(authInterceptor)
        .build();
}
```

---

## Logging Interceptor

```java
@Component @Slf4j
public class LoggingInterceptor implements ServerInterceptor {

    @Override
    public <R, S> ServerCall.Listener<R> interceptCall(
            ServerCall<R, S> call, Metadata headers, ServerCallHandler<R, S> next) {

        String method = call.getMethodDescriptor().getBareMethodName();
        String service = call.getMethodDescriptor().getServiceName();
        long startTime = System.currentTimeMillis();

        log.debug("gRPC call started: {}/{}", service, method);

        ServerCall<R, S> loggingCall = new ForwardingServerCall.SimpleForwardingServerCall<>(call) {
            @Override
            public void close(Status status, Metadata trailers) {
                long duration = System.currentTimeMillis() - startTime;
                if (status.isOk()) {
                    log.debug("gRPC call completed: {}/{} in {}ms", service, method, duration);
                } else {
                    log.warn("gRPC call failed: {}/{} status={} in {}ms",
                        service, method, status.getCode(), duration);
                }
                super.close(status, trailers);
            }
        };

        return next.startCall(loggingCall, headers);
    }
}
```

---

## Metrics Interceptor

```java
@Component @RequiredArgsConstructor
public class MetricsInterceptor implements ServerInterceptor {
    private final MeterRegistry meterRegistry;

    @Override
    public <R, S> ServerCall.Listener<R> interceptCall(
            ServerCall<R, S> call, Metadata headers, ServerCallHandler<R, S> next) {

        String method = call.getMethodDescriptor().getBareMethodName();
        Timer.Sample sample = Timer.start(meterRegistry);

        ServerCall<R, S> metricsCall = new ForwardingServerCall.SimpleForwardingServerCall<>(call) {
            @Override
            public void close(Status status, Metadata trailers) {
                sample.stop(meterRegistry.timer("grpc.server.calls",
                    "method", method,
                    "status", status.getCode().name()));
                if (!status.isOk()) {
                    meterRegistry.counter("grpc.server.errors",
                        "method", method,
                        "status", status.getCode().name()).increment();
                }
                super.close(status, trailers);
            }
        };

        meterRegistry.counter("grpc.server.calls.total", "method", method).increment();
        return next.startCall(metricsCall, headers);
    }
}
```

---

## Retry Interceptor (Client)

```java
@Component
public class RetryInterceptor implements ClientInterceptor {
    private static final Set<Status.Code> RETRYABLE_CODES = Set.of(
        Status.Code.UNAVAILABLE, Status.Code.RESOURCE_EXHAUSTED);

    @Override
    public <R, S> ClientCall<R, S> interceptCall(
            MethodDescriptor<R, S> method, CallOptions options, Channel next) {

        // Only retry unary calls (streaming retry is complex)
        if (method.getType() != MethodDescriptor.MethodType.UNARY) {
            return next.newCall(method, options);
        }

        return new RetryingClientCall<>(next.newCall(method, options),
            next, method, options, RETRYABLE_CODES, 3);
    }
}

// Better approach: use gRPC built-in retry via service config (see reactive-advanced.md)
// Or use client-side retry via Reactor operators (Mono.retryWhen)
```
