---
name: grpc-patterns
description: >
  Comprehensive gRPC patterns for Java Spring applications. Covers proto file
  design, Spring Boot gRPC integration with grpc-spring-boot-starter, server
  and client implementation, reactive gRPC with reactor-grpc, error handling,
  interceptors, streaming patterns, security, testing, monitoring, and common
  anti-patterns. Use when building gRPC services with Spring Boot 3.x and Java 17+.
version: 1.0.0
---

# gRPC Patterns for Spring Boot

Production-ready gRPC patterns for Java 17+ / Spring Boot 3.x applications.

## Quick Reference

| Category | When to Use | Jump To |
|----------|------------|---------|
| Proto Design | Defining service contracts | [Proto Design](#proto-file-design) |
| Proto Best Practices | Versioning, compatibility | [Proto Best Practices](#proto-best-practices) |
| Server Implementation | Building gRPC services | [Server](#server-implementation) |
| Client Implementation | Consuming gRPC services | [Client](#client-implementation) |
| Reactive gRPC | WebFlux + gRPC | [Reactive gRPC](#reactive-grpc) |
| Error Handling | Status codes, error details | [Error Handling](#error-handling) |
| Interceptors | Auth, logging, metrics | [Interceptors](#interceptors) |
| Streaming | All streaming patterns | [Streaming](#streaming-patterns) |
| Deadlines | Timeout management | [Deadlines](#deadline--timeout-management) |
| Load Balancing | Client-side, service mesh | [Load Balancing](#load-balancing) |
| Health Checks | Health checking protocol | [Health Checks](#health-checks) |
| Testing | InProcessServer, mocks | [Testing](#testing) |
| Security | TLS, JWT auth | [Security](#security) |
| Monitoring | Micrometer metrics | [Monitoring](#monitoring) |
| Anti-Patterns | Common mistakes | [Anti-Patterns](#common-anti-patterns) |

---

## Dependencies

```xml
<!-- gRPC Spring Boot Starter (net.devh) -->
<dependency>
    <groupId>net.devh</groupId>
    <artifactId>grpc-spring-boot-starter</artifactId>
    <version>3.1.0.RELEASE</version>
</dependency>

<!-- For server only -->
<dependency>
    <groupId>net.devh</groupId>
    <artifactId>grpc-server-spring-boot-starter</artifactId>
    <version>3.1.0.RELEASE</version>
</dependency>

<!-- For client only -->
<dependency>
    <groupId>net.devh</groupId>
    <artifactId>grpc-client-spring-boot-starter</artifactId>
    <version>3.1.0.RELEASE</version>
</dependency>

<!-- Protobuf -->
<dependency>
    <groupId>com.google.protobuf</groupId>
    <artifactId>protobuf-java</artifactId>
    <version>3.25.3</version>
</dependency>

<!-- gRPC Core -->
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-netty-shaded</artifactId>
</dependency>
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-protobuf</artifactId>
</dependency>
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-stub</artifactId>
</dependency>

<!-- Reactive gRPC (reactor-grpc) -->
<dependency>
    <groupId>com.salesforce.servicelibs</groupId>
    <artifactId>reactor-grpc-stub</artifactId>
    <version>1.2.4</version>
</dependency>

<!-- Error Details (google.rpc) -->
<dependency>
    <groupId>com.google.api.grpc</groupId>
    <artifactId>proto-google-common-protos</artifactId>
    <version>2.33.0</version>
</dependency>

<!-- gRPC Testing -->
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-testing</artifactId>
    <scope>test</scope>
</dependency>

<!-- Protobuf Maven Plugin -->
<!-- In <build><plugins> -->
<plugin>
    <groupId>org.xolstice.maven.plugins</groupId>
    <artifactId>protobuf-maven-plugin</artifactId>
    <version>0.6.1</version>
    <configuration>
        <protocArtifact>com.google.protobuf:protoc:3.25.3:exe:${os.detected.classifier}</protocArtifact>
        <pluginId>grpc-java</pluginId>
        <pluginArtifact>io.grpc:protoc-gen-grpc-java:1.63.0:exe:${os.detected.classifier}</pluginArtifact>
        <protocPlugins>
            <protocPlugin>
                <id>reactor-grpc</id>
                <groupId>com.salesforce.servicelibs</groupId>
                <artifactId>reactor-grpc</artifactId>
                <version>1.2.4</version>
                <mainClass>com.salesforce.reactorgrpc.ReactorGrpcGenerator</mainClass>
            </protocPlugin>
        </protocPlugins>
    </configuration>
    <executions>
        <execution>
            <goals>
                <goal>compile</goal>
                <goal>compile-custom</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

---

## Proto File Design

### Service Definition

```protobuf
// src/main/proto/user_service.proto
syntax = "proto3";

package com.example.user.v1;

option java_multiple_files = true;
option java_package = "com.example.user.v1";
option java_outer_classname = "UserServiceProto";

import "google/protobuf/timestamp.proto";
import "google/protobuf/empty.proto";
import "google/protobuf/wrappers.proto";
import "google/protobuf/field_mask.proto";

// Service definition
service UserService {
  // Unary RPCs
  rpc GetUser(GetUserRequest) returns (User);
  rpc CreateUser(CreateUserRequest) returns (User);
  rpc UpdateUser(UpdateUserRequest) returns (User);
  rpc DeleteUser(DeleteUserRequest) returns (google.protobuf.Empty);

  // Server streaming
  rpc ListUsers(ListUsersRequest) returns (stream User);

  // Client streaming
  rpc BulkCreateUsers(stream CreateUserRequest) returns (BulkCreateResponse);

  // Bidirectional streaming
  rpc SyncUsers(stream UserSyncRequest) returns (stream UserSyncResponse);
}
```

### Message Types

```protobuf
// Request/Response messages
message GetUserRequest {
  int64 id = 1;
}

message CreateUserRequest {
  string email = 1;
  string name = 2;
  UserRole role = 3;
  map<string, string> metadata = 4;
}

message UpdateUserRequest {
  int64 id = 1;
  google.protobuf.StringValue name = 2;        // wrapper = optional update
  google.protobuf.StringValue email = 3;
  UserRole role = 4;
  google.protobuf.FieldMask update_mask = 5;    // partial updates
}

message DeleteUserRequest {
  int64 id = 1;
}

message ListUsersRequest {
  int32 page_size = 1;
  string page_token = 2;     // cursor for pagination
  string filter = 3;          // e.g., "role=ADMIN"
  string order_by = 4;        // e.g., "created_at desc"
}

message BulkCreateResponse {
  int32 created_count = 1;
  repeated string failed_emails = 2;
}

// Entity message
message User {
  int64 id = 1;
  string email = 2;
  string name = 3;
  UserRole role = 4;
  bool active = 5;
  google.protobuf.Timestamp created_at = 6;
  google.protobuf.Timestamp updated_at = 7;
  map<string, string> metadata = 8;

  // Nested message
  Address address = 9;
}

message Address {
  string street = 1;
  string city = 2;
  string country = 3;
  string postal_code = 4;
}

// Enums
enum UserRole {
  USER_ROLE_UNSPECIFIED = 0;    // Always have 0 = unspecified
  USER_ROLE_USER = 1;
  USER_ROLE_ADMIN = 2;
  USER_ROLE_MODERATOR = 3;
}

// Oneof — mutually exclusive fields
message Notification {
  string id = 1;

  oneof channel {
    EmailNotification email = 2;
    SmsNotification sms = 3;
    PushNotification push = 4;
  }
}

message EmailNotification {
  string subject = 1;
  string body = 2;
}

message SmsNotification {
  string phone_number = 1;
  string message = 2;
}

message PushNotification {
  string device_token = 1;
  string title = 2;
  string body = 3;
}

// Streaming messages
message UserSyncRequest {
  oneof action {
    User upsert = 1;
    int64 delete_id = 2;
  }
}

message UserSyncResponse {
  int64 id = 1;
  SyncStatus status = 2;
  string error_message = 3;
}

enum SyncStatus {
  SYNC_STATUS_UNSPECIFIED = 0;
  SYNC_STATUS_CREATED = 1;
  SYNC_STATUS_UPDATED = 2;
  SYNC_STATUS_DELETED = 3;
  SYNC_STATUS_FAILED = 4;
}
```

---

## Proto Best Practices

### Field Numbering Rules

| Range | Usage |
|-------|-------|
| 1–15 | Frequent fields (1 byte to encode tag) |
| 16–2047 | Less frequent fields (2 bytes) |
| 19000–19999 | Reserved by protobuf (do NOT use) |
| 1–536870911 | Maximum valid field number |

### Backward Compatibility Rules

```protobuf
// ✅ SAFE changes (backward compatible):
// - Add new fields with new numbers
// - Add new enum values
// - Add new RPC methods to service
// - Change field name (wire format uses number, not name)
// - Add new oneof members
// - Change int32 ↔ int64, uint32 ↔ uint64

// ❌ BREAKING changes:
// - Delete or reuse field numbers
// - Change field type incompatibly (string → int32)
// - Change field number
// - Remove enum values
// - Change package name
// - Change RPC signature

// Reserve deleted fields to prevent reuse
message User {
  reserved 6, 8 to 10;
  reserved "old_field_name", "deprecated_field";
  // ...
}
```

### Versioning Strategy

```
proto/
├── com/example/user/
│   ├── v1/                    # Version 1 (stable)
│   │   └── user_service.proto
│   └── v2/                    # Version 2 (breaking changes)
│       └── user_service.proto
```

```protobuf
// v1 — stable, don't modify breaking
package com.example.user.v1;

// v2 — new version with breaking changes
package com.example.user.v2;
```

---

## Server Implementation

### Basic gRPC Service

```java
@GrpcService
@RequiredArgsConstructor
public class UserGrpcService extends UserServiceGrpc.UserServiceImplBase {

    private final UserService userService;
    private final UserProtoMapper mapper;

    @Override
    public void getUser(GetUserRequest request, StreamObserver<User> responseObserver) {
        try {
            var user = userService.findById(request.getId());
            if (user == null) {
                responseObserver.onError(Status.NOT_FOUND
                    .withDescription("User not found: " + request.getId())
                    .asRuntimeException());
                return;
            }
            responseObserver.onNext(mapper.toProto(user));
            responseObserver.onCompleted();
        } catch (Exception e) {
            responseObserver.onError(Status.INTERNAL
                .withDescription("Internal error")
                .withCause(e)
                .asRuntimeException());
        }
    }

    @Override
    public void createUser(CreateUserRequest request, StreamObserver<User> responseObserver) {
        try {
            var dto = mapper.toDto(request);
            var created = userService.create(dto);
            responseObserver.onNext(mapper.toProto(created));
            responseObserver.onCompleted();
        } catch (DuplicateEmailException e) {
            responseObserver.onError(Status.ALREADY_EXISTS
                .withDescription("Email already exists: " + request.getEmail())
                .asRuntimeException());
        } catch (ValidationException e) {
            responseObserver.onError(Status.INVALID_ARGUMENT
                .withDescription(e.getMessage())
                .asRuntimeException());
        }
    }

    @Override
    public void listUsers(ListUsersRequest request, StreamObserver<User> responseObserver) {
        try {
            var users = userService.list(request.getPageSize(), request.getPageToken());
            users.forEach(user -> responseObserver.onNext(mapper.toProto(user)));
            responseObserver.onCompleted();
        } catch (Exception e) {
            responseObserver.onError(Status.INTERNAL
                .withDescription("Failed to list users")
                .withCause(e)
                .asRuntimeException());
        }
    }
}
```

### Server Configuration

```yaml
# application.yml
grpc:
  server:
    port: 9090
    security:
      enabled: false            # Set true for TLS
      certificateChain: classpath:cert/server.crt
      privateKey: classpath:cert/server.key
    max-inbound-message-size: 4MB
    max-inbound-metadata-size: 8KB
    keep-alive-time: 30s
    keep-alive-timeout: 5s
    permit-keep-alive-without-calls: true
    in-process-name: test       # For in-process testing
```

---

## Client Implementation

### Client Configuration

```yaml
# application.yml
grpc:
  client:
    user-service:
      address: dns:///user-service:9090
      negotiation-type: PLAINTEXT    # or TLS
      enable-keep-alive: true
      keep-alive-time: 30s
      keep-alive-timeout: 5s
      deadline: 10s                   # default deadline
```

### Stub Types

```java
@Service
@RequiredArgsConstructor
public class UserGrpcClient {

    // Blocking stub — synchronous calls
    @GrpcClient("user-service")
    private UserServiceGrpc.UserServiceBlockingStub blockingStub;

    // Async stub — callback-based
    @GrpcClient("user-service")
    private UserServiceGrpc.UserServiceStub asyncStub;

    // Future stub — returns ListenableFuture (unary only)
    @GrpcClient("user-service")
    private UserServiceGrpc.UserServiceFutureStub futureStub;

    // Blocking call
    public UserDto getUser(Long id) {
        var request = GetUserRequest.newBuilder()
            .setId(id)
            .build();

        try {
            var response = blockingStub
                .withDeadlineAfter(5, TimeUnit.SECONDS)
                .getUser(request);
            return mapper.toDto(response);
        } catch (StatusRuntimeException e) {
            return switch (e.getStatus().getCode()) {
                case NOT_FOUND -> throw new UserNotFoundException(id);
                case DEADLINE_EXCEEDED -> throw new TimeoutException("User service timeout");
                default -> throw new ServiceException("gRPC error: " + e.getStatus());
            };
        }
    }

    // Async call
    public void getUserAsync(Long id, Consumer<UserDto> onSuccess, Consumer<Throwable> onError) {
        var request = GetUserRequest.newBuilder().setId(id).build();

        asyncStub.withDeadlineAfter(5, TimeUnit.SECONDS)
            .getUser(request, new StreamObserver<>() {
                @Override
                public void onNext(User user) {
                    onSuccess.accept(mapper.toDto(user));
                }

                @Override
                public void onError(Throwable t) {
                    onError.accept(t);
                }

                @Override
                public void onCompleted() {
                    // done
                }
            });
    }

    // Future stub call
    public CompletableFuture<UserDto> getUserFuture(Long id) {
        var request = GetUserRequest.newBuilder().setId(id).build();
        var future = futureStub
            .withDeadlineAfter(5, TimeUnit.SECONDS)
            .getUser(request);

        return CompletableFuture.supplyAsync(() -> {
            try {
                return mapper.toDto(future.get());
            } catch (Exception e) {
                throw new CompletionException(e);
            }
        });
    }
}
```

---

## Reactive gRPC

### Reactor-gRPC Stubs

```java
// Generated by reactor-grpc plugin: ReactorUserServiceGrpc

@Service
@RequiredArgsConstructor
public class UserReactiveGrpcClient {

    @GrpcClient("user-service")
    private ReactorUserServiceGrpc.ReactorUserServiceStub reactorStub;

    // Unary — returns Mono
    public Mono<UserDto> getUser(Long id) {
        var request = GetUserRequest.newBuilder().setId(id).build();
        return reactorStub.getUser(request)
            .map(mapper::toDto)
            .timeout(Duration.ofSeconds(5))
            .onErrorMap(StatusRuntimeException.class, this::mapGrpcError);
    }

    // Server streaming — returns Flux
    public Flux<UserDto> listUsers(int pageSize) {
        var request = ListUsersRequest.newBuilder()
            .setPageSize(pageSize)
            .build();
        return reactorStub.listUsers(request)
            .map(mapper::toDto);
    }

    // Client streaming — accepts Flux, returns Mono
    public Mono<BulkCreateResponse> bulkCreate(Flux<CreateUserRequest> requests) {
        return reactorStub.bulkCreateUsers(requests);
    }

    // Bidirectional streaming — Flux in, Flux out
    public Flux<UserSyncResponse> syncUsers(Flux<UserSyncRequest> requests) {
        return reactorStub.syncUsers(requests);
    }

    private Throwable mapGrpcError(StatusRuntimeException e) {
        return switch (e.getStatus().getCode()) {
            case NOT_FOUND -> new NotFoundException(e.getStatus().getDescription());
            case ALREADY_EXISTS -> new ConflictException(e.getStatus().getDescription());
            case INVALID_ARGUMENT -> new BadRequestException(e.getStatus().getDescription());
            case DEADLINE_EXCEEDED -> new TimeoutException("gRPC deadline exceeded");
            case UNAVAILABLE -> new ServiceUnavailableException("Service unavailable");
            default -> new InternalException("gRPC error: " + e.getStatus());
        };
    }
}
```

### Reactive Server Implementation

```java
@GrpcService
@RequiredArgsConstructor
public class UserReactiveGrpcService extends ReactorUserServiceGrpc.UserServiceImplBase {

    private final UserService userService;
    private final UserProtoMapper mapper;

    @Override
    public Mono<User> getUser(Mono<GetUserRequest> request) {
        return request
            .flatMap(req -> userService.findById(req.getId()))
            .map(mapper::toProto)
            .switchIfEmpty(Mono.error(Status.NOT_FOUND
                .withDescription("User not found")
                .asRuntimeException()));
    }

    @Override
    public Flux<User> listUsers(Mono<ListUsersRequest> request) {
        return request.flatMapMany(req ->
            userService.findAll(req.getPageSize(), req.getPageToken())
                .map(mapper::toProto));
    }

    @Override
    public Mono<BulkCreateResponse> bulkCreateUsers(Flux<CreateUserRequest> requests) {
        return requests
            .map(mapper::toDto)
            .flatMap(dto -> userService.create(dto)
                .onErrorResume(e -> {
                    log.warn("Failed to create user: {}", e.getMessage());
                    return Mono.empty();
                }))
            .count()
            .map(count -> BulkCreateResponse.newBuilder()
                .setCreatedCount(count.intValue())
                .build());
    }

    @Override
    public Flux<UserSyncResponse> syncUsers(Flux<UserSyncRequest> requests) {
        return requests.flatMap(req -> {
            if (req.hasUpsert()) {
                return userService.upsert(mapper.toDto(req.getUpsert()))
                    .map(user -> UserSyncResponse.newBuilder()
                        .setId(user.id())
                        .setStatus(SyncStatus.SYNC_STATUS_UPDATED)
                        .build());
            } else {
                return userService.delete(req.getDeleteId())
                    .thenReturn(UserSyncResponse.newBuilder()
                        .setId(req.getDeleteId())
                        .setStatus(SyncStatus.SYNC_STATUS_DELETED)
                        .build());
            }
        });
    }
}
```

---

## Error Handling

### gRPC Status Codes — When to Use

| Status Code | HTTP Equiv. | When to Use |
|-------------|-------------|-------------|
| `OK` | 200 | Success |
| `INVALID_ARGUMENT` | 400 | Validation error, bad request |
| `NOT_FOUND` | 404 | Resource not found |
| `ALREADY_EXISTS` | 409 | Duplicate resource |
| `PERMISSION_DENIED` | 403 | Authenticated but not authorized |
| `UNAUTHENTICATED` | 401 | No valid credentials |
| `RESOURCE_EXHAUSTED` | 429 | Rate limited, quota exceeded |
| `FAILED_PRECONDITION` | 400 | Precondition not met (e.g., non-empty dir) |
| `ABORTED` | 409 | Concurrency conflict (optimistic lock) |
| `UNIMPLEMENTED` | 501 | Method not implemented |
| `INTERNAL` | 500 | Unexpected server error |
| `UNAVAILABLE` | 503 | Transient error, client should retry |
| `DEADLINE_EXCEEDED` | 504 | Timeout |
| `CANCELLED` | 499 | Client cancelled request |
| `DATA_LOSS` | 500 | Unrecoverable data loss |

### Rich Error Details (google.rpc.Status)

```java
import com.google.rpc.Status;
import com.google.rpc.BadRequest;
import com.google.rpc.ErrorInfo;
import io.grpc.protobuf.StatusProto;

// Sending rich error details
public void createUser(CreateUserRequest request, StreamObserver<User> responseObserver) {
    var violations = validate(request);
    if (!violations.isEmpty()) {
        var badRequest = BadRequest.newBuilder();
        violations.forEach(v -> badRequest.addFieldViolations(
            BadRequest.FieldViolation.newBuilder()
                .setField(v.field())
                .setDescription(v.message())
                .build()
        ));

        var status = Status.newBuilder()
            .setCode(io.grpc.Status.INVALID_ARGUMENT.getCode().value())
            .setMessage("Validation failed")
            .addDetails(Any.pack(badRequest.build()))
            .build();

        responseObserver.onError(StatusProto.toStatusRuntimeException(status));
        return;
    }
    // ...
}

// ErrorInfo for domain-specific errors
private StatusRuntimeException createBusinessError(String reason, String domain) {
    var errorInfo = ErrorInfo.newBuilder()
        .setReason(reason)
        .setDomain(domain)
        .putMetadata("service", "user-service")
        .putMetadata("timestamp", Instant.now().toString())
        .build();

    var status = Status.newBuilder()
        .setCode(io.grpc.Status.FAILED_PRECONDITION.getCode().value())
        .setMessage(reason)
        .addDetails(Any.pack(errorInfo))
        .build();

    return StatusProto.toStatusRuntimeException(status);
}
```

### Extracting Error Details (Client Side)

```java
try {
    var user = blockingStub.createUser(request);
} catch (StatusRuntimeException e) {
    var status = StatusProto.fromThrowable(e);
    if (status != null) {
        for (var detail : status.getDetailsList()) {
            if (detail.is(BadRequest.class)) {
                var badRequest = detail.unpack(BadRequest.class);
                badRequest.getFieldViolationsList().forEach(v ->
                    log.error("Field {}: {}", v.getField(), v.getDescription()));
            }
            if (detail.is(ErrorInfo.class)) {
                var errorInfo = detail.unpack(ErrorInfo.class);
                log.error("Reason: {}, Domain: {}",
                    errorInfo.getReason(), errorInfo.getDomain());
            }
        }
    }
}
```

---

## Interceptors

### Server Interceptor — Authentication

```java
@Component
public class JwtAuthInterceptor implements ServerInterceptor {

    private final JwtValidator jwtValidator;

    public static final Context.Key<String> USER_ID_KEY = Context.key("userId");
    public static final Context.Key<Set<String>> ROLES_KEY = Context.key("roles");

    // Methods that don't require auth
    private static final Set<String> PUBLIC_METHODS = Set.of(
        "grpc.health.v1.Health/Check",
        "grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo"
    );

    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call,
            Metadata headers,
            ServerCallHandler<ReqT, RespT> next) {

        String methodName = call.getMethodDescriptor().getFullMethodName();
        if (PUBLIC_METHODS.contains(methodName)) {
            return next.startCall(call, headers);
        }

        String token = headers.get(
            Metadata.Key.of("authorization", Metadata.ASCII_STRING_MARSHALLER));

        if (token == null || !token.startsWith("Bearer ")) {
            call.close(io.grpc.Status.UNAUTHENTICATED
                .withDescription("Missing or invalid authorization header"), headers);
            return new ServerCall.Listener<>() {};
        }

        try {
            var claims = jwtValidator.validate(token.substring(7));
            var context = Context.current()
                .withValue(USER_ID_KEY, claims.getSubject())
                .withValue(ROLES_KEY, claims.getRoles());
            return Contexts.interceptCall(context, call, headers, next);
        } catch (JwtException e) {
            call.close(io.grpc.Status.UNAUTHENTICATED
                .withDescription("Invalid token: " + e.getMessage()), headers);
            return new ServerCall.Listener<>() {};
        }
    }
}
```

### Server Interceptor — Logging

```java
@Component
@Slf4j
public class LoggingInterceptor implements ServerInterceptor {

    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call,
            Metadata headers,
            ServerCallHandler<ReqT, RespT> next) {

        String methodName = call.getMethodDescriptor().getFullMethodName();
        long startTime = System.nanoTime();

        var wrappedCall = new ForwardingServerCall.SimpleForwardingServerCall<>(call) {
            @Override
            public void close(io.grpc.Status status, Metadata trailers) {
                long duration = (System.nanoTime() - startTime) / 1_000_000;
                log.info("gRPC {} — status={} duration={}ms",
                    methodName, status.getCode(), duration);
                super.close(status, trailers);
            }
        };

        var listener = next.startCall(wrappedCall, headers);

        return new ForwardingServerCallListener.SimpleForwardingServerCallListener<>(listener) {
            @Override
            public void onMessage(ReqT message) {
                log.debug("gRPC {} request: {}", methodName, message);
                super.onMessage(message);
            }
        };
    }
}
```

### Server Interceptor — Deadline Propagation

```java
@Component
public class DeadlinePropagationInterceptor implements ServerInterceptor {

    private static final long DEFAULT_DEADLINE_MS = 30_000;

    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call,
            Metadata headers,
            ServerCallHandler<ReqT, RespT> next) {

        var deadline = Context.current().getDeadline();
        if (deadline == null) {
            // Set default deadline if none provided
            var context = Context.current()
                .withDeadlineAfter(DEFAULT_DEADLINE_MS, TimeUnit.MILLISECONDS,
                    Executors.newSingleThreadScheduledExecutor());
            return Contexts.interceptCall(context, call, headers, next);
        }

        return next.startCall(call, headers);
    }
}
```

### Client Interceptor — Metadata Propagation

```java
@Component
public class MetadataPropagationInterceptor implements ClientInterceptor {

    private static final Metadata.Key<String> TRACE_ID_KEY =
        Metadata.Key.of("x-trace-id", Metadata.ASCII_STRING_MARSHALLER);

    @Override
    public <ReqT, RespT> ClientCall<ReqT, RespT> interceptCall(
            MethodDescriptor<ReqT, RespT> method,
            CallOptions callOptions,
            Channel next) {

        return new ForwardingClientCall.SimpleForwardingClientCall<>(
                next.newCall(method, callOptions)) {
            @Override
            public void start(Listener<RespT> responseListener, Metadata headers) {
                String traceId = MDC.get("traceId");
                if (traceId != null) {
                    headers.put(TRACE_ID_KEY, traceId);
                }
                super.start(responseListener, headers);
            }
        };
    }
}
```

### Registering Interceptors

```java
// Server interceptors — auto-detected if @Component + ServerInterceptor
// Or explicitly configure order:
@Configuration
public class GrpcServerConfig {

    @Bean
    public GlobalServerInterceptorConfigurer serverInterceptorConfigurer(
            JwtAuthInterceptor authInterceptor,
            LoggingInterceptor loggingInterceptor) {
        return registry -> {
            registry.add(loggingInterceptor);   // first
            registry.add(authInterceptor);       // second
        };
    }
}

// Client interceptors
@Configuration
public class GrpcClientConfig {

    @Bean
    public GlobalClientInterceptorConfigurer clientInterceptorConfigurer(
            MetadataPropagationInterceptor metadataInterceptor) {
        return registry -> registry.add(metadataInterceptor);
    }
}
```

---

## Streaming Patterns

### Server Streaming — Large Result Sets

```java
// Server implementation
@Override
public void listUsers(ListUsersRequest request, StreamObserver<User> responseObserver) {
    int pageSize = Math.min(request.getPageSize(), 100);
    String cursor = request.getPageToken();

    try {
        while (true) {
            var page = userService.findPage(pageSize, cursor);
            for (var user : page.items()) {
                responseObserver.onNext(mapper.toProto(user));
            }
            if (!page.hasNext()) break;
            cursor = page.nextCursor();
        }
        responseObserver.onCompleted();
    } catch (Exception e) {
        responseObserver.onError(Status.INTERNAL
            .withDescription("Failed to stream users")
            .withCause(e)
            .asRuntimeException());
    }
}

// Client consuming server stream
public List<UserDto> listAllUsers() {
    var request = ListUsersRequest.newBuilder().setPageSize(100).build();
    var users = new ArrayList<UserDto>();

    var iterator = blockingStub.listUsers(request);
    iterator.forEachRemaining(user -> users.add(mapper.toDto(user)));

    return users;
}
```

### Client Streaming — Bulk Upload

```java
// Server implementation
@Override
public StreamObserver<CreateUserRequest> bulkCreateUsers(
        StreamObserver<BulkCreateResponse> responseObserver) {

    var created = new AtomicInteger(0);
    var failed = new CopyOnWriteArrayList<String>();

    return new StreamObserver<>() {
        @Override
        public void onNext(CreateUserRequest request) {
            try {
                userService.create(mapper.toDto(request));
                created.incrementAndGet();
            } catch (Exception e) {
                failed.add(request.getEmail());
            }
        }

        @Override
        public void onError(Throwable t) {
            log.error("Client stream error", t);
        }

        @Override
        public void onCompleted() {
            responseObserver.onNext(BulkCreateResponse.newBuilder()
                .setCreatedCount(created.get())
                .addAllFailedEmails(failed)
                .build());
            responseObserver.onCompleted();
        }
    };
}

// Client sending stream
public BulkCreateResponse bulkCreate(List<CreateUserDto> users) {
    var responseFuture = new CompletableFuture<BulkCreateResponse>();

    var requestObserver = asyncStub.bulkCreateUsers(new StreamObserver<>() {
        @Override
        public void onNext(BulkCreateResponse response) {
            responseFuture.complete(response);
        }

        @Override
        public void onError(Throwable t) {
            responseFuture.completeExceptionally(t);
        }

        @Override
        public void onCompleted() {}
    });

    for (var user : users) {
        requestObserver.onNext(mapper.toProto(user));
    }
    requestObserver.onCompleted();

    return responseFuture.join();
}
```

### Bidirectional Streaming

```java
// Server implementation
@Override
public StreamObserver<UserSyncRequest> syncUsers(
        StreamObserver<UserSyncResponse> responseObserver) {

    return new StreamObserver<>() {
        @Override
        public void onNext(UserSyncRequest request) {
            try {
                UserSyncResponse response;
                if (request.hasUpsert()) {
                    var user = userService.upsert(mapper.toDto(request.getUpsert()));
                    response = UserSyncResponse.newBuilder()
                        .setId(user.id())
                        .setStatus(SyncStatus.SYNC_STATUS_UPDATED)
                        .build();
                } else {
                    userService.delete(request.getDeleteId());
                    response = UserSyncResponse.newBuilder()
                        .setId(request.getDeleteId())
                        .setStatus(SyncStatus.SYNC_STATUS_DELETED)
                        .build();
                }
                responseObserver.onNext(response);
            } catch (Exception e) {
                responseObserver.onNext(UserSyncResponse.newBuilder()
                    .setStatus(SyncStatus.SYNC_STATUS_FAILED)
                    .setErrorMessage(e.getMessage())
                    .build());
            }
        }

        @Override
        public void onError(Throwable t) {
            log.error("Sync stream error", t);
        }

        @Override
        public void onCompleted() {
            responseObserver.onCompleted();
        }
    };
}
```

---

## Deadline / Timeout Management

```java
// Client — set deadline per call
var response = blockingStub
    .withDeadlineAfter(5, TimeUnit.SECONDS)
    .getUser(request);

// Client — set deadline from context
var deadline = Context.current().getDeadline();
if (deadline != null) {
    long remaining = deadline.timeRemaining(TimeUnit.MILLISECONDS);
    stub = stub.withDeadlineAfter(remaining, TimeUnit.MILLISECONDS);
}

// Server — check deadline before expensive work
@Override
public void heavyOperation(Request request, StreamObserver<Response> responseObserver) {
    if (Context.current().isCancelled()) {
        responseObserver.onError(Status.CANCELLED
            .withDescription("Client cancelled")
            .asRuntimeException());
        return;
    }

    // Check deadline before each batch in long operations
    for (var batch : batches) {
        if (Context.current().getDeadline() != null
                && Context.current().getDeadline().isExpired()) {
            responseObserver.onError(Status.DEADLINE_EXCEEDED
                .withDescription("Deadline exceeded during processing")
                .asRuntimeException());
            return;
        }
        processBatch(batch);
    }
}

// Default deadline via client config
// application.yml
// grpc.client.user-service.deadline: 10s
```

---

## Load Balancing

### Client-Side Load Balancing

```yaml
# application.yml
grpc:
  client:
    user-service:
      address: dns:///user-service:9090
      default-load-balancing-policy: round_robin
      negotiation-type: PLAINTEXT
```

```java
// Programmatic configuration
@Bean
public GrpcChannelConfigurer channelConfigurer() {
    return (channelBuilder, name) -> {
        if ("user-service".equals(name)) {
            channelBuilder.defaultLoadBalancingPolicy("round_robin");
        }
    };
}
```

### Service Discovery (Kubernetes / Consul)

```yaml
# With Kubernetes headless service
grpc:
  client:
    user-service:
      address: dns:///user-service.default.svc.cluster.local:9090
      default-load-balancing-policy: round_robin

# With static list
grpc:
  client:
    user-service:
      address: static://host1:9090,host2:9090,host3:9090
      default-load-balancing-policy: round_robin
```

---

## Health Checks

```java
// Auto-configured by grpc-spring-boot-starter
// Accessible at: grpc.health.v1.Health/Check

// Custom health indicator
@Component
public class DatabaseHealthIndicator extends AbstractHealthIndicator {

    private final DatabaseClient databaseClient;

    @Override
    protected void doHealthCheck(Health.Builder builder) {
        try {
            databaseClient.sql("SELECT 1").fetch().first().block();
            builder.up();
        } catch (Exception e) {
            builder.down(e);
        }
    }
}
```

```yaml
# Enable gRPC health check
grpc:
  server:
    health-service-enabled: true
```

```bash
# Test health with grpcurl
grpcurl -plaintext localhost:9090 grpc.health.v1.Health/Check
```

---

## Testing

### InProcessServer Tests

```java
@SpringBootTest(properties = {
    "grpc.server.in-process-name=test",
    "grpc.server.port=-1",
    "grpc.client.user-service.address=in-process:test"
})
class UserGrpcServiceTest {

    @GrpcClient("user-service")
    private UserServiceGrpc.UserServiceBlockingStub stub;

    @MockBean
    private UserService userService;

    @Test
    void shouldGetUser() {
        when(userService.findById(1L))
            .thenReturn(new UserDto(1L, "test@example.com", "Test"));

        var response = stub.getUser(
            GetUserRequest.newBuilder().setId(1).build());

        assertThat(response.getEmail()).isEqualTo("test@example.com");
        assertThat(response.getName()).isEqualTo("Test");
    }

    @Test
    void shouldReturnNotFoundForMissingUser() {
        when(userService.findById(999L)).thenReturn(null);

        var exception = assertThrows(StatusRuntimeException.class,
            () -> stub.getUser(GetUserRequest.newBuilder().setId(999).build()));

        assertThat(exception.getStatus().getCode()).isEqualTo(Status.NOT_FOUND.getCode());
    }

    @Test
    void shouldStreamUsers() {
        when(userService.list(anyInt(), any()))
            .thenReturn(new Page<>(List.of(
                new UserDto(1L, "a@test.com", "A"),
                new UserDto(2L, "b@test.com", "B")
            ), false, null));

        var iterator = stub.listUsers(
            ListUsersRequest.newBuilder().setPageSize(10).build());

        var users = new ArrayList<User>();
        iterator.forEachRemaining(users::add);

        assertThat(users).hasSize(2);
    }
}
```

### Reactive gRPC Testing

```java
@SpringBootTest(properties = {
    "grpc.server.in-process-name=test",
    "grpc.server.port=-1",
    "grpc.client.user-service.address=in-process:test"
})
class UserReactiveGrpcServiceTest {

    @GrpcClient("user-service")
    private ReactorUserServiceGrpc.ReactorUserServiceStub reactorStub;

    @MockBean
    private UserService userService;

    @Test
    void shouldGetUserReactively() {
        when(userService.findById(1L))
            .thenReturn(Mono.just(new UserDto(1L, "test@example.com", "Test")));

        StepVerifier.create(
            reactorStub.getUser(GetUserRequest.newBuilder().setId(1).build()))
            .assertNext(user -> {
                assertThat(user.getEmail()).isEqualTo("test@example.com");
            })
            .verifyComplete();
    }
}
```

---

## Proto-to-DTO Mapping

```java
@Component
public class UserProtoMapper {

    public UserDto toDto(User proto) {
        return new UserDto(
            proto.getId(),
            proto.getEmail(),
            proto.getName(),
            mapRole(proto.getRole()),
            proto.getActive(),
            toInstant(proto.getCreatedAt()),
            toInstant(proto.getUpdatedAt())
        );
    }

    public User toProto(UserDto dto) {
        var builder = User.newBuilder()
            .setId(dto.id())
            .setEmail(dto.email())
            .setName(dto.name())
            .setRole(mapRole(dto.role()))
            .setActive(dto.active());

        if (dto.createdAt() != null) {
            builder.setCreatedAt(toTimestamp(dto.createdAt()));
        }
        if (dto.updatedAt() != null) {
            builder.setUpdatedAt(toTimestamp(dto.updatedAt()));
        }

        return builder.build();
    }

    public CreateUserDto toDto(CreateUserRequest request) {
        return new CreateUserDto(
            request.getEmail(),
            request.getName(),
            mapRole(request.getRole())
        );
    }

    // Timestamp conversions
    private Instant toInstant(Timestamp ts) {
        if (ts == null || ts.equals(Timestamp.getDefaultInstance())) return null;
        return Instant.ofEpochSecond(ts.getSeconds(), ts.getNanos());
    }

    private Timestamp toTimestamp(Instant instant) {
        return Timestamp.newBuilder()
            .setSeconds(instant.getEpochSecond())
            .setNanos(instant.getNano())
            .build();
    }

    // Enum mapping
    private String mapRole(UserRole role) {
        return switch (role) {
            case USER_ROLE_ADMIN -> "ADMIN";
            case USER_ROLE_MODERATOR -> "MODERATOR";
            default -> "USER";
        };
    }

    private UserRole mapRole(String role) {
        return switch (role) {
            case "ADMIN" -> UserRole.USER_ROLE_ADMIN;
            case "MODERATOR" -> UserRole.USER_ROLE_MODERATOR;
            default -> UserRole.USER_ROLE_USER;
        };
    }
}
```

---

## Security

### TLS Configuration

```yaml
# Server TLS
grpc:
  server:
    security:
      enabled: true
      certificate-chain: classpath:certs/server.crt
      private-key: classpath:certs/server.key
      client-auth: OPTIONAL          # NONE, OPTIONAL, REQUIRE
      trust-certificate-collection: classpath:certs/ca.crt

# Client TLS
grpc:
  client:
    user-service:
      address: dns:///user-service:9090
      negotiation-type: TLS
      security:
        certificate-chain: classpath:certs/client.crt
        private-key: classpath:certs/client.key
        trust-certificate-collection: classpath:certs/ca.crt
```

### JWT Authentication via Interceptor

```java
// See JwtAuthInterceptor in Interceptors section above
// Access user context in service:
@GrpcService
public class SecuredGrpcService extends SecuredServiceGrpc.SecuredServiceImplBase {

    @Override
    public void securedMethod(Request request, StreamObserver<Response> responseObserver) {
        String userId = JwtAuthInterceptor.USER_ID_KEY.get();
        Set<String> roles = JwtAuthInterceptor.ROLES_KEY.get();

        if (!roles.contains("ADMIN")) {
            responseObserver.onError(Status.PERMISSION_DENIED
                .withDescription("Admin role required")
                .asRuntimeException());
            return;
        }

        // ... process request with userId context
    }
}
```

---

## Monitoring

### Micrometer Metrics for gRPC

```xml
<dependency>
    <groupId>net.devh</groupId>
    <artifactId>grpc-spring-boot-starter</artifactId>
    <version>3.1.0.RELEASE</version>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

```yaml
# application.yml
grpc:
  server:
    enable-metrics: true
  client:
    GLOBAL:
      enable-metrics: true

management:
  endpoints:
    web:
      exposure:
        include: health, prometheus, info
```

```java
// Custom metrics interceptor
@Component
public class MetricsInterceptor implements ServerInterceptor {

    private final MeterRegistry meterRegistry;
    private final Timer grpcTimer;

    public MetricsInterceptor(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
        this.grpcTimer = Timer.builder("grpc.server.requests")
            .description("gRPC server request duration")
            .register(meterRegistry);
    }

    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call,
            Metadata headers,
            ServerCallHandler<ReqT, RespT> next) {

        String methodName = call.getMethodDescriptor().getFullMethodName();
        Timer.Sample sample = Timer.start(meterRegistry);

        var wrappedCall = new ForwardingServerCall.SimpleForwardingServerCall<>(call) {
            @Override
            public void close(io.grpc.Status status, Metadata trailers) {
                sample.stop(Timer.builder("grpc.server.requests")
                    .tag("method", methodName)
                    .tag("status", status.getCode().name())
                    .register(meterRegistry));

                meterRegistry.counter("grpc.server.calls",
                    "method", methodName,
                    "status", status.getCode().name()
                ).increment();

                super.close(status, trailers);
            }
        };

        return next.startCall(wrappedCall, headers);
    }
}
```

### gRPC Reflection (for grpcurl/debugging)

```xml
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-services</artifactId>
</dependency>
```

```yaml
grpc:
  server:
    reflection-service-enabled: true  # Enable in dev/staging, disable in prod
```

```bash
# List services
grpcurl -plaintext localhost:9090 list

# Describe service
grpcurl -plaintext localhost:9090 describe com.example.user.v1.UserService

# Call unary RPC
grpcurl -plaintext -d '{"id": 1}' localhost:9090 com.example.user.v1.UserService/GetUser
```

---

## Common Anti-Patterns

### ❌ Not Setting Deadlines

```java
// WRONG — no deadline, call can hang forever
var response = blockingStub.getUser(request); // ❌

// CORRECT — always set deadline
var response = blockingStub
    .withDeadlineAfter(5, TimeUnit.SECONDS) // ✅
    .getUser(request);
```

### ❌ Ignoring Status Codes

```java
// WRONG — catch-all swallows important errors
try {
    var user = blockingStub.getUser(request);
} catch (StatusRuntimeException e) {
    log.error("gRPC error", e); // ❌ no distinction
}

// CORRECT — handle specific status codes
try {
    var user = blockingStub.getUser(request);
} catch (StatusRuntimeException e) {
    switch (e.getStatus().getCode()) {
        case NOT_FOUND -> throw new UserNotFoundException(id);
        case DEADLINE_EXCEEDED -> throw new TimeoutException("Timeout");
        case UNAVAILABLE -> throw new RetryableException(e);
        default -> throw new ServiceException("Unexpected gRPC error", e);
    }
}
```

### ❌ Using INTERNAL for All Errors

```java
// WRONG — everything is INTERNAL
responseObserver.onError(Status.INTERNAL.asRuntimeException()); // ❌

// CORRECT — use appropriate status codes
// Validation → INVALID_ARGUMENT
// Not found → NOT_FOUND
// Duplicate → ALREADY_EXISTS
// Auth → UNAUTHENTICATED / PERMISSION_DENIED
// Retryable → UNAVAILABLE
// Truly internal → INTERNAL
```

### ❌ Large Messages Without Streaming

```java
// WRONG — sending 10k users in one response
rpc GetAllUsers(Empty) returns (AllUsersResponse); // ❌ can be huge

// CORRECT — use server streaming
rpc ListUsers(ListUsersRequest) returns (stream User); // ✅ backpressure-friendly
```

### ❌ Not Handling Stream Errors

```java
// WRONG — no error handling on stream
asyncStub.listUsers(request, new StreamObserver<>() {
    @Override
    public void onNext(User user) { process(user); }

    @Override
    public void onError(Throwable t) {} // ❌ silently swallows errors

    @Override
    public void onCompleted() {}
});

// CORRECT — handle and log errors
asyncStub.listUsers(request, new StreamObserver<>() {
    @Override
    public void onNext(User user) { process(user); }

    @Override
    public void onError(Throwable t) {
        if (t instanceof StatusRuntimeException sre) {
            log.error("Stream error: {} - {}",
                sre.getStatus().getCode(),
                sre.getStatus().getDescription());
        } else {
            log.error("Unexpected stream error", t);
        }
    }

    @Override
    public void onCompleted() { log.info("Stream completed"); }
});
```

### ❌ Reusing Field Numbers After Deletion

```protobuf
// WRONG — reusing deleted field number
message User {
  string name = 1;
  // string old_field = 2; (deleted)
  string new_field = 2;  // ❌ reuses number 2!
}

// CORRECT — reserve deleted field numbers
message User {
  string name = 1;
  reserved 2;             // ✅ prevents reuse
  string new_field = 3;   // ✅ new number
}
```

---

## Checklist

- [ ] Deadlines set on every client call
- [ ] Appropriate Status codes (not INTERNAL for everything)
- [ ] Rich error details for validation errors (BadRequest)
- [ ] Auth interceptor on server, token propagation on client
- [ ] Logging interceptor with method name and duration
- [ ] Streaming for large result sets (not single mega-response)
- [ ] Reserved fields for deleted proto fields
- [ ] Proto versioning strategy (package-based)
- [ ] Health check enabled
- [ ] Metrics with Micrometer (method, status tags)
- [ ] Reflection enabled only in non-production
- [ ] TLS in production
- [ ] InProcess tests for service logic
- [ ] Integration tests with real gRPC calls