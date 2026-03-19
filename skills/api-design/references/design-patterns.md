# API Design Patterns Reference

Detailed pagination, filtering, sorting, field selection, content negotiation, HATEOAS, and OpenAPI config.

## Table of Contents
- [Cursor Pagination](#cursor-pagination)
- [Keyset Pagination](#keyset-pagination)
- [Filtering & Sorting](#filtering--sorting)
- [Field Selection (Sparse Fieldsets)](#field-selection-sparse-fieldsets)
- [Content Negotiation](#content-negotiation)
- [HATEOAS](#hateoas)
- [OpenAPI Configuration](#openapi-configuration)

---

## Cursor Pagination

Encodes page state in an opaque token — no drift when items are inserted/deleted.

```java
// Response DTO
public record CursorPage<T>(
    List<T> content,
    String nextCursor,   // null if last page
    String prevCursor,   // null if first page
    boolean hasNext,
    int size
) {}

// Cursor = base64(lastId + "|" + lastCreatedAt)
public class CursorEncoder {
    public static String encode(String id, Instant createdAt) {
        String raw = id + "|" + createdAt.toEpochMilli();
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(raw.getBytes());
    }

    public static CursorData decode(String cursor) {
        String raw = new String(Base64.getUrlDecoder().decode(cursor));
        String[] parts = raw.split("\\|");
        return new CursorData(parts[0], Instant.ofEpochMilli(Long.parseLong(parts[1])));
    }

    public record CursorData(String id, Instant createdAt) {}
}
```

```java
// Repository query
@Query("""
    SELECT * FROM orders
    WHERE (created_at, id) < (:createdAt, :id)
    ORDER BY created_at DESC, id DESC
    LIMIT :limit
    """)
Flux<Order> findBeforeCursor(Instant createdAt, String id, int limit);
```

```java
// Service
public Mono<CursorPage<OrderResponse>> findPage(String cursor, int size) {
    if (cursor == null) {
        return orderRepository.findTopN(size + 1)
            .collectList()
            .map(items -> buildPage(items, size));
    }
    var data = CursorEncoder.decode(cursor);
    return orderRepository.findBeforeCursor(data.createdAt(), data.id(), size + 1)
        .collectList()
        .map(items -> buildPage(items, size));
}

private CursorPage<OrderResponse> buildPage(List<Order> items, int size) {
    boolean hasNext = items.size() > size;
    var page = hasNext ? items.subList(0, size) : items;
    String nextCursor = hasNext
        ? CursorEncoder.encode(page.get(page.size() - 1).id(),
            page.get(page.size() - 1).createdAt())
        : null;
    return new CursorPage<>(page.stream().map(mapper::toResponse).toList(),
        nextCursor, null, hasNext, size);
}
```

---

## Keyset Pagination

Best for large datasets — uses composite index for O(log N) performance.

```java
// URL: GET /api/v1/orders?afterId=abc&afterCreatedAt=2024-01-15T10:00:00Z&size=20
@GetMapping
public Flux<OrderResponse> list(
        @RequestParam(required = false) String afterId,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME)
            Instant afterCreatedAt,
        @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {

    if (afterId == null) {
        return orderRepository.findTopN(size).map(mapper::toResponse);
    }
    return orderRepository.findAfterKeyset(afterCreatedAt, afterId, size)
        .map(mapper::toResponse);
}
```

```sql
-- Requires composite index: CREATE INDEX idx_orders_keyset ON orders(created_at DESC, id DESC)
SELECT * FROM orders
WHERE (created_at, id) < (:afterCreatedAt, :afterId)
ORDER BY created_at DESC, id DESC
LIMIT :size
```

---

## Filtering & Sorting

```java
// Filter params as record (validated)
public record OrderFilter(
    @RequestParam(required = false) OrderStatus status,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant fromDate,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant toDate,
    @RequestParam(required = false) @Min(0) BigDecimal minAmount,
    @RequestParam(required = false) @Min(0) BigDecimal maxAmount
) {}

// Sort field whitelist — CRITICAL: prevents injection
private static final Set<String> ALLOWED_SORT_FIELDS =
    Set.of("createdAt", "amount", "status", "customerId");

@GetMapping
public Flux<OrderResponse> list(OrderFilter filter,
        @RequestParam(defaultValue = "createdAt") String sortBy,
        @RequestParam(defaultValue = "DESC") Sort.Direction direction) {

    if (!ALLOWED_SORT_FIELDS.contains(sortBy)) {
        return Flux.error(new BadRequestException("Invalid sort field: " + sortBy));
    }
    return orderRepository.findWithFilter(filter, Sort.by(direction, sortBy))
        .map(mapper::toResponse);
}
```

```java
// Dynamic query with DatabaseClient
public Flux<Order> findWithFilter(OrderFilter filter, Sort sort) {
    var sql = new StringBuilder("SELECT * FROM orders WHERE 1=1");
    var params = new HashMap<String, Object>();

    if (filter.status() != null) {
        sql.append(" AND status = :status");
        params.put("status", filter.status().name());
    }
    if (filter.fromDate() != null) {
        sql.append(" AND created_at >= :fromDate");
        params.put("fromDate", filter.fromDate());
    }
    if (filter.toDate() != null) {
        sql.append(" AND created_at <= :toDate");
        params.put("toDate", filter.toDate());
    }

    // Append sort (field already whitelisted)
    sort.forEach(order ->
        sql.append(" ORDER BY ").append(order.getProperty())
           .append(" ").append(order.getDirection()));

    var spec = databaseClient.sql(sql.toString());
    for (var entry : params.entrySet()) {
        spec = spec.bind(entry.getKey(), entry.getValue());
    }
    return spec.map(row -> mapRow(row)).all();
}
```

---

## Field Selection (Sparse Fieldsets)

Reduces payload size — useful for list endpoints.

```java
// URL: GET /api/v1/users?fields=id,email,name
@GetMapping
public Mono<Map<String, Object>> getUser(
        @PathVariable String id,
        @RequestParam(required = false) Set<String> fields) {

    return userService.findById(id)
        .map(user -> filterFields(mapper.toResponse(user), fields));
}

private Map<String, Object> filterFields(UserResponse response, Set<String> fields) {
    if (fields == null || fields.isEmpty()) {
        return mapper.toMap(response);  // return all
    }
    var allowed = Set.of("id", "email", "name", "role", "createdAt");  // whitelist
    return mapper.toMap(response).entrySet().stream()
        .filter(e -> fields.contains(e.getKey()) && allowed.contains(e.getKey()))
        .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
}
```

---

## Content Negotiation

```java
// Versioning via Accept header (alternative to URI versioning)
@GetMapping(produces = {
    "application/vnd.api.v2+json",
    MediaType.APPLICATION_JSON_VALUE
})
public Mono<UserResponseV2> getUserV2(@PathVariable String id) { ... }

@GetMapping(produces = "application/vnd.api.v1+json")
public Mono<UserResponseV1> getUserV1(@PathVariable String id) { ... }
```

```java
// CSV export via content negotiation
@GetMapping(produces = {MediaType.APPLICATION_JSON_VALUE, "text/csv"})
public Mono<ResponseEntity<?>> exportOrders(
        @RequestHeader(HttpHeaders.ACCEPT) MediaType accept) {
    if (accept.includes(MediaType.parseMediaType("text/csv"))) {
        return orderService.findAll()
            .map(this::toCsvRow)
            .collect(Collectors.joining("\n"))
            .map(csv -> ResponseEntity.ok()
                .header("Content-Disposition", "attachment; filename=orders.csv")
                .contentType(MediaType.parseMediaType("text/csv"))
                .body(csv));
    }
    return orderService.findAll().collectList()
        .map(orders -> ResponseEntity.ok().body(orders));
}
```

---

## HATEOAS

Spring HATEOAS with WebFlux:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-hateoas</artifactId>
</dependency>
```

```java
// Response with links
public class OrderModel extends RepresentationModel<OrderModel> {
    private String id;
    private OrderStatus status;
    private BigDecimal totalAmount;
    // getters/setters or use @Data
}

// Assembler
@Component
public class OrderModelAssembler implements
        ReactiveRepresentationModelAssembler<Order, OrderModel> {

    @Override
    public Mono<OrderModel> toModel(Order order, ServerWebExchange exchange) {
        var model = new OrderModel();
        model.setId(order.getId());
        model.setStatus(order.getStatus());
        model.setTotalAmount(order.getTotalAmount());

        model.add(linkTo(methodOn(OrderController.class).getById(order.getId())).withSelfRel());

        if (order.getStatus() == OrderStatus.PENDING) {
            model.add(linkTo(methodOn(OrderController.class)
                .cancel(order.getId())).withRel("cancel"));
            model.add(linkTo(methodOn(OrderController.class)
                .confirm(order.getId())).withRel("confirm"));
        }
        return Mono.just(model);
    }
}
```

```json
{
  "id": "ord-123",
  "status": "PENDING",
  "totalAmount": 99.99,
  "_links": {
    "self": { "href": "/api/v1/orders/ord-123" },
    "cancel": { "href": "/api/v1/orders/ord-123/cancel" },
    "confirm": { "href": "/api/v1/orders/ord-123/confirm" }
  }
}
```

---

## OpenAPI Configuration

```java
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
            .info(new Info()
                .title("Order Service API")
                .version("v1")
                .description("Manages customer orders")
                .contact(new Contact().name("Platform Team").email("platform@example.com")))
            .addSecurityItem(new SecurityRequirement().addList("bearerAuth"))
            .components(new Components()
                .addSecuritySchemes("bearerAuth",
                    new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("bearer")
                        .bearerFormat("JWT")));
    }
}
```

```java
// Controller annotations
@Operation(summary = "Create order",
           description = "Creates a new order and returns 201 with Location header")
@ApiResponses({
    @ApiResponse(responseCode = "201", description = "Order created",
        headers = @Header(name = "Location", description = "URL of created order")),
    @ApiResponse(responseCode = "400", description = "Validation error",
        content = @Content(schema = @Schema(implementation = ProblemDetail.class))),
    @ApiResponse(responseCode = "401", description = "Unauthorized")
})
@PostMapping
@ResponseStatus(HttpStatus.CREATED)
public Mono<OrderResponse> create(
        @Valid @RequestBody
        @io.swagger.v3.oas.annotations.parameters.RequestBody(
            description = "Order creation request",
            required = true)
        CreateOrderRequest request) { ... }
```

```yaml
# application.yml — Swagger UI
springdoc:
  swagger-ui:
    path: /swagger-ui.html
    operations-sorter: method
    tags-sorter: alpha
  api-docs:
    path: /api-docs
  show-actuator: false
```
