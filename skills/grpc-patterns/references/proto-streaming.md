# Proto Design & Streaming Reference

Full proto rules, best practices, backward compatibility, and all 4 streaming patterns.

## Table of Contents
- [Proto Design Rules](#proto-design-rules)
- [Field Numbering](#field-numbering)
- [Backward Compatibility](#backward-compatibility)
- [Well-Known Types](#well-known-types)
- [Unary RPC](#unary-rpc)
- [Server Streaming](#server-streaming)
- [Client Streaming](#client-streaming)
- [Bidirectional Streaming](#bidirectional-streaming)
- [Error Details (google.rpc.Status)](#error-details-googlerpcstatus)

---

## Proto Design Rules

```protobuf
syntax = "proto3";
package com.example.order.v1;  // versioned package

option java_multiple_files = true;  // one class per message (required)
option java_package = "com.example.order.v1";
option java_outer_classname = "OrderProto";  // only used if multiple_files=false

// ✅ Good: Versioned service name
service OrderServiceV1 {
    // unary
    rpc CreateOrder (CreateOrderRequest) returns (CreateOrderResponse);
    // server streaming
    rpc ListOrders  (ListOrdersRequest)  returns (stream OrderResponse);
    // client streaming
    rpc BatchCreate (stream CreateOrderRequest) returns (BatchCreateResponse);
    // bidirectional
    rpc ProcessOrders(stream OrderEvent)  returns (stream OrderAck);
}

// Always wrap in request/response messages — even for simple params
// ✅ Good
message GetOrderRequest { string order_id = 1; }
// ❌ Bad — can't add fields later
// rpc GetOrder (google.protobuf.StringValue) returns (OrderResponse);

// Enum — always 0 as UNSPECIFIED
enum OrderStatus {
    ORDER_STATUS_UNSPECIFIED = 0;  // ← required
    ORDER_STATUS_CREATED = 1;
    ORDER_STATUS_CONFIRMED = 2;
    ORDER_STATUS_SHIPPED = 3;
    ORDER_STATUS_DELIVERED = 4;
    ORDER_STATUS_CANCELLED = 5;
}
```

---

## Field Numbering

```protobuf
message CreateOrderRequest {
    // Fields 1-15: single byte (use for frequent fields)
    string customer_id = 1;         // high frequency → low number
    repeated OrderItem items = 2;
    string idempotency_key = 3;     // always include for mutations

    // Fields 16-2047: two bytes
    Address shipping_address = 16;  // less frequent → higher number
    map<string, string> metadata = 17;

    // Reserved — never reuse field numbers or names (causes silent corruption)
    reserved 4, 5, 6;
    reserved "old_field_name";
}
```

**Rules:**
- Never change field numbers once deployed
- Never change field types
- Use `reserved` for deleted fields — prevents reuse
- Lower numbers → smaller message size for common fields

---

## Backward Compatibility

```protobuf
// v1 message
message OrderResponse {
    string order_id = 1;
    string status = 2;
}

// v2 — backward compatible changes (new optional fields only)
message OrderResponse {
    string order_id = 1;
    string status = 2;
    google.protobuf.Timestamp created_at = 3;  // NEW — old clients ignore
    optional string tracking_number = 4;        // NEW — optional
    // ❌ NEVER: rename fields, change types, remove non-reserved fields
    // ❌ NEVER: change repeated ↔ singular, required ↔ optional
}

// Breaking changes require a new service version
service OrderServiceV2 { ... }  // bump to v2
```

---

## Well-Known Types

```protobuf
import "google/protobuf/timestamp.proto";
import "google/protobuf/duration.proto";
import "google/protobuf/wrappers.proto";  // nullable primitives
import "google/protobuf/empty.proto";     // void responses
import "google/rpc/status.proto";         // error details
import "google/rpc/error_details.proto";

message OrderResponse {
    google.protobuf.Timestamp created_at = 1;  // use instead of int64
    google.protobuf.Duration processing_time = 2;
    google.protobuf.StringValue optional_note = 3;  // nullable string
}

// Void response
rpc DeleteOrder (DeleteOrderRequest) returns (google.protobuf.Empty);
```

---

## Unary RPC

Standard request/response. Most common pattern.

```java
@GrpcService
public class OrderGrpcService extends OrderServiceGrpc.OrderServiceImplBase {

    @Override
    public void createOrder(CreateOrderRequest request,
                            StreamObserver<CreateOrderResponse> responseObserver) {
        try {
            Order order = orderService.create(toCommand(request));
            responseObserver.onNext(toProto(order));
            responseObserver.onCompleted();
        } catch (ValidationException e) {
            responseObserver.onError(Status.INVALID_ARGUMENT
                .withDescription(e.getMessage()).asRuntimeException());
        }
    }
}

// Blocking client
OrderServiceGrpc.OrderServiceBlockingStub stub = OrderServiceGrpc.newBlockingStub(channel);
CreateOrderResponse response = stub.withDeadlineAfter(5, TimeUnit.SECONDS)
    .createOrder(request);
```

---

## Server Streaming

Server sends multiple responses to single request. Use for: large data sets, real-time updates, export.

```java
// Server
@Override
public void listOrders(ListOrdersRequest request,
                       StreamObserver<OrderResponse> responseObserver) {
    try {
        orderService.findByCustomer(request.getCustomerId())
            .forEach(order -> responseObserver.onNext(toProto(order)));
        responseObserver.onCompleted();
    } catch (Exception e) {
        responseObserver.onError(Status.INTERNAL.withCause(e).asRuntimeException());
    }
}

// Reactive server
@GrpcService
public class ReactiveOrderService extends ReactorOrderServiceGrpc.OrderServiceImplBase {
    @Override
    public Flux<OrderResponse> listOrders(Mono<ListOrdersRequest> request) {
        return request
            .flatMapMany(req -> orderService.findByCustomer(req.getCustomerId()))
            .map(this::toProto);
    }
}

// Blocking client (iterates responses)
Iterator<OrderResponse> responses = stub.listOrders(request);
while (responses.hasNext()) {
    OrderResponse order = responses.next();
    // process each
}
```

---

## Client Streaming

Client sends multiple requests, server responds once. Use for: batch upload, file upload.

```java
// Server
@Override
public StreamObserver<CreateOrderRequest> batchCreate(
        StreamObserver<BatchCreateResponse> responseObserver) {
    List<Order> created = new ArrayList<>();
    return new StreamObserver<>() {
        @Override
        public void onNext(CreateOrderRequest request) {
            created.add(orderService.create(toCommand(request)));
        }

        @Override
        public void onError(Throwable t) {
            log.error("Client stream error", t);
            responseObserver.onError(Status.INTERNAL.withCause(t).asRuntimeException());
        }

        @Override
        public void onCompleted() {
            responseObserver.onNext(BatchCreateResponse.newBuilder()
                .setCreatedCount(created.size())
                .build());
            responseObserver.onCompleted();
        }
    };
}

// Reactive server
@Override
public Mono<BatchCreateResponse> batchCreate(Flux<CreateOrderRequest> requests) {
    return requests
        .flatMap(req -> orderService.create(toCommand(req)))
        .count()
        .map(count -> BatchCreateResponse.newBuilder().setCreatedCount(count).build());
}

// Async client
StreamObserver<CreateOrderRequest> requestObserver = stub.batchCreate(responseObserver);
orders.forEach(order -> requestObserver.onNext(toRequest(order)));
requestObserver.onCompleted();
```

---

## Bidirectional Streaming

Both sides stream simultaneously. Use for: chat, real-time processing, low-latency pipelines.

```java
// Server
@Override
public StreamObserver<OrderEvent> processOrders(StreamObserver<OrderAck> responseObserver) {
    return new StreamObserver<>() {
        @Override
        public void onNext(OrderEvent event) {
            // Process and immediately respond
            orderService.processAsync(event)
                .subscribe(result ->
                    responseObserver.onNext(OrderAck.newBuilder()
                        .setOrderId(event.getOrderId())
                        .setSuccess(result.isSuccess())
                        .build()));
        }

        @Override
        public void onError(Throwable t) {
            log.error("Bidi stream error", t);
        }

        @Override
        public void onCompleted() {
            responseObserver.onCompleted();
        }
    };
}

// Reactive server
@Override
public Flux<OrderAck> processOrders(Flux<OrderEvent> events) {
    return events.flatMap(event ->
        orderService.processAsync(event)
            .map(result -> OrderAck.newBuilder()
                .setOrderId(event.getOrderId())
                .setSuccess(result.isSuccess())
                .build()));
}
```

---

## Error Details (google.rpc.Status)

Rich error details beyond simple status code.

```java
// Server — send rich error
private Throwable richError(String message, List<FieldViolation> violations) {
    BadRequest badRequest = BadRequest.newBuilder()
        .addAllFieldViolations(violations)
        .build();
    com.google.rpc.Status status = com.google.rpc.Status.newBuilder()
        .setCode(Code.INVALID_ARGUMENT.getNumber())
        .setMessage(message)
        .addDetails(Any.pack(badRequest))
        .build();
    return StatusProto.toStatusRuntimeException(status);
}

// Client — extract error details
try {
    stub.createOrder(request);
} catch (StatusRuntimeException e) {
    com.google.rpc.Status status = StatusProto.fromThrowable(e);
    if (status != null) {
        for (Any detail : status.getDetailsList()) {
            if (detail.is(BadRequest.class)) {
                BadRequest badRequest = detail.unpack(BadRequest.class);
                badRequest.getFieldViolationsList().forEach(v ->
                    log.error("Field {} invalid: {}", v.getField(), v.getDescription()));
            }
        }
    }
}
```
