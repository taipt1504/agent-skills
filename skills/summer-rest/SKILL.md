---
name: summer-rest
description: Summer Framework REST patterns — handler pattern (RequestHandler, @Handler, SpringBus, BaseController), ResponseFactory, SummerGlobalExceptionHandler, Jackson auto-configuration, WebClientBuilderFactory with pooled connections.
triggers:
  natural: ["summer handler", "request handler", "summer controller"]
  code: ["BaseController", "@Handler", "RequestHandler", "WebClientBuilderFactory"]
requires: ["summer-core", "api-design"]
applicability:
  always: false
  triggers:
    files_match: ["**/*Controller*.java", "**/*Handler*.java", "**/*Router*.java"]
    code_patterns: ["io.f8a.summer.rest", "BaseController", "RequestHandler", "@Handler", "WebClientBuilderFactory"]
    task_keywords: ["summer REST", "summer handler", "BaseController.execute", "SpringBus", "request handler"]
    related_skills: ["spring-webflux-patterns", "api-design"]
    related_rules:
      - rules/java/api-design.md
relevance_assessment: |
  HIGH 90%+: new endpoint using BaseController + RequestHandler dispatch
  HIGH 80%+: existing handler modification within Summer REST pattern
  MEDIUM 40-79%: WebClient builder factory usage
  LOW 1-39%: vanilla Spring controller in Summer project (should migrate)
  ZERO: project lacks io.f8a.summer:summer-rest
---

# Summer REST — Handlers, WebClient & Exception Handling

**Gate:** Verify summer-core loaded and `io.f8a.summer:summer-platform` in build.gradle before proceeding.

**Module:** `summer-rest-autoconfigure` | **Config:** `f8a.common`

## API Path Routing

ALL APIs MUST use correct path prefix based on audience:

| Prefix | Audience | Auth | Description |
|--------|----------|------|-------------|
| `/bo/api/**` | Backoffice | Authen realm `backoffice` | Admin/CMS APIs |
| `/internal/api/**` | Internal service | Không expose qua API Gateway | Service-to-service calls |
| `/partner/api/**` | Partner | JWT tại gateway (tuỳ chọn) | Third-party integrations |
| `/public/api/**` | Public | Không authen | Open APIs |
| `/api/**` | End User | Authen realm `user` | Consumer-facing APIs |

**URL structure** follows api-design standard with prefix:
- **Resource mapping** (controller): `/{prefix}/api/${resource}` → `@RequestMapping("/bo/api/orders")`
- **Path APIs** (method): `/${versioning}/...` → `@GetMapping("/v1")`, `@GetMapping("/v1/{id}")`
- **End-user**: `/api/${resource}` → `@RequestMapping("/api/orders")`

```
# Backoffice: @RequestMapping("/bo/api/users")
GET    /bo/api/users/v1                 # List users (backoffice)
POST   /bo/api/orders/v1/123/approve    # Approve order

# Internal: @RequestMapping("/internal/api/notifications")
POST   /internal/api/notifications/v1   # Send notification (service-to-service)

# Partner: @RequestMapping("/partner/api/products")
GET    /partner/api/products/v1         # Partner product listing

# Public: @RequestMapping("/public/api/health")
GET    /public/api/health/v1            # Health check
GET    /public/api/configs/v1           # Public configs

# End User: @RequestMapping("/api/orders") — standard per api-design skill
GET    /api/orders/v1               # User's orders
POST   /api/orders/v1               # Create order
GET    /api/orders/v1/123           # Get order by ID
```

**SecurityConfig** must whitelist by prefix:
```java
return http.authorizeExchange(auth -> auth
    .pathMatchers("/actuator/**").permitAll()
    .pathMatchers("/public/api/**").permitAll()
    .pathMatchers("/internal/api/**").permitAll()  // Gateway blocks external access
    .anyExchange().authenticated()).build();
```

## Handler Pattern

1. Define request DTO (with validation) + response DTO
2. Handler extends `RequestHandler<Req, Res>`, annotated `@Component`
3. Controller extends `BaseController`, calls `execute(request)` → routes through `SpringBus`
4. Use `@RestTransactional` for reactive transactions

```java
// Handler
@Component
public class CreateOrderHandler extends RequestHandler<CreateOrderRequest, Order> {
    @Override
    public Mono<Order> handle(CreateOrderRequest req) { /* ... */ }
}

// Backoffice controller — /{prefix}/api/{resource}
@RestController @RequestMapping("/bo/api/orders")
public class BoOrderController extends BaseController {
    @PostMapping("/v1")
    public Mono<ResponseEntity<Order>> create(@Valid @RequestBody CreateOrderRequest req) {
        return execute(req); // auto-routes to CreateOrderHandler
    }

    @PostMapping("/v1/{id}/approve")
    public Mono<ResponseEntity<Order>> approve(@PathVariable String id) {
        return execute(new ApproveOrderRequest(id));
    }
}

// End-user controller — /api/{resource} (standard)
@RestController @RequestMapping("/api/orders")
public class OrderController extends BaseController {
    @PostMapping("/v1")
    public Mono<ResponseEntity<Order>> create(@Valid @RequestBody CreateOrderRequest req) {
        return execute(req);
    }
}
```

**Registry** scans `@Handler`/`RequestHandler` beans at startup, maps request type → handler.

Use `@RestTransactional` on handler methods that require reactive transaction management:

```java
@RestTransactional
@Override
public Mono<Order> handle(CreateOrderRequest req) { ... }
```

## ResponseFactory

Auto-registered bean for `ResponseEntity` wrappers:
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

Auto-configured via `f8a.common.jackson`. Defaults: camelCase, ISO-8601, no nulls, enums as toString, UTC. Modules: JavaTimeModule, Jdk8Module, ParameterNamesModule.

## WebClientBuilderFactory

Pooled `WebClient` with trace propagation:
```java
WebClient client = factory.newClient(
    WebClientBuilderOptions.builder()
        .baseUrl("https://api.example.com")
        .errorHandling(false).build());
```

Config: `f8a.common.webclient` — max-connections (100), connect-timeout (10s), read-timeout (30s), max-idle-time (30s), max-life-time (5m).

## Logging Config

`f8a.common.logging` controls AOP-based request/response logging. See `references/handler-examples.md` for full YAML block (`log-headers`, `log-request-body`, `log-response-body` flags).

## Version Notes

- **0.2.1:** `GlobalExceptionHandler` → `SummerGlobalExceptionHandler`; `JsonErrorResponse` → `core.exception`; gains `timestamp` + `details`; `ViewableException` gains fluent `.detail()`; `DownstreamException` maps to 500 (was 502)
- **0.2.1:** Custom tracing removed; use Micrometer + OpenTelemetry (`micrometer-tracing-bridge-otel` + `opentelemetry-exporter-otlp`)

See `references/handler-examples.md` for full CRUD, pagination, and optimistic locking examples.

## Rules

- Always correct path prefix: `/bo/api/**` (backoffice), `/internal/api/**` (internal), `/partner/api/**` (partner), `/public/api/**` (public), `/api/**` (end-user) — wrong prefix = wrong auth realm.
- Always extend `BaseController` — provides SpringBus routing.
- Always `RequestHandler<Req, Res>` for business logic — never logic in controllers.
- Always `@Valid` on `@RequestBody` parameters.
- Always versioned method paths: `@GetMapping("/v1")`, `@PostMapping("/v1/{id}")` — never omit version.
- Never throw generic exceptions — use `ViewableException` via enum pattern (see summer-core).
- Never return entities directly — use response DTOs.

## Related Skills

- **summer-core** — Shared types (ViewableException, Member, CallerAware)
- **summer-security** — @AuthRoles for endpoint authorization
- **api-design** — REST conventions, pagination, RFC 7807
