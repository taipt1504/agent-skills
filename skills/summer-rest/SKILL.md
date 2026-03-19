---
name: summer-rest
description: >
  Summer Framework REST patterns — handler pattern (RequestHandler, @Handler,
  SpringBus, BaseController), ResponseFactory, SummerGlobalExceptionHandler,
  Jackson auto-configuration, WebClientBuilderFactory with pooled connections.
triggers:
  - RequestHandler
  - BaseController
  - SpringBus
  - ResponseFactory
  - WebClientBuilderFactory
  - SummerGlobalExceptionHandler
  - f8a.common
  - "@Handler"
  - handler pattern
  - summer rest
  - summer webclient
---

# Summer REST — Handlers, WebClient & Exception Handling

**Module:** `summer-rest-autoconfigure` | **Config:** `f8a.common`

## Handler Pattern

1. Define request DTO (with validation) + response DTO
2. Create handler extending `RequestHandler<Req, Res>` annotated `@Component`
3. Controller extends `BaseController`, calls `execute(request)` which routes through `SpringBus`
4. Use `@RestTransactional` for reactive transactions

```java
// Handler
@Component
public class CreateOrderHandler extends RequestHandler<CreateOrderRequest, Order> {
    @Override
    public Mono<Order> handle(CreateOrderRequest req) { /* ... */ }
}

// Controller
@RestController @RequestMapping("/api/orders")
public class OrderController extends BaseController {
    @PostMapping
    public Mono<ResponseEntity<Order>> create(@Valid @RequestBody CreateOrderRequest req) {
        return execute(req); // auto-routes to CreateOrderHandler
    }
}
```

**Registry** scans `@Handler`/`RequestHandler` beans at startup, maps request type to handler.

## ResponseFactory

Auto-registered bean for building `ResponseEntity` wrappers:
```java
responseFactory.success(data);  // Mono<ResponseEntity<T>>
```

## Exception Handling

`SummerGlobalExceptionHandler` (0.2.1+) implements `ErrorWebExceptionHandler`. Reads traceId from MDC.

Handles: `ViewableException`, `AccessDeniedException`, `AuthenticationException`, `NoResourceFoundException`, `MethodNotAllowedException`, `NotAcceptableStatusException`, `UnsupportedMediaTypeStatusException`, `PayloadTooLargeException`, `IllegalArgumentException`, `IllegalStateException`.

Custom exception enum pattern:
```java
@Getter @RequiredArgsConstructor
public enum OrderExceptions implements IntoViewableException {
    ORDER_NOT_FOUND("order.not.found", HttpStatus.NOT_FOUND);
    public static final String PREFIX = "ord";
    private final String code;
    private final HttpStatus httpStatus;
    @Override
    public ViewableException toException() {
        return new ViewableException(PREFIX + "." + code, httpStatus);
    }
}
```

## Jackson Config

Auto-configured via `f8a.common.jackson`. Defaults: camelCase, ISO-8601 dates, no nulls, enums as toString, UTC. Modules: JavaTimeModule, Jdk8Module, ParameterNamesModule.

## WebClientBuilderFactory

Pooled `WebClient` with trace propagation:
```java
WebClient client = factory.newClient(
    WebClientBuilderOptions.builder()
        .baseUrl("https://api.example.com")
        .errorHandling(false).build());
```

Config: `f8a.common.webclient` — max-connections (100), connect-timeout (10s), read-timeout (30s), max-idle-time (30s), max-life-time (5m).

## Version Notes

- **0.2.1:** `GlobalExceptionHandler` renamed to `SummerGlobalExceptionHandler`; `JsonErrorResponse` moved to `core.exception`; gains `timestamp` + `details` fields; `ViewableException` gains fluent `.detail()` builder; `DownstreamException` maps to 500 (was 502)
- **0.2.1:** Custom tracing removed; use Micrometer + OpenTelemetry (`micrometer-tracing-bridge-otel` + `opentelemetry-exporter-otlp`)

See `references/handler-examples.md` for full CRUD, pagination, and optimistic locking handler examples.
