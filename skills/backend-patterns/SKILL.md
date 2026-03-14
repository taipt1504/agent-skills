---
name: backend-patterns
description: Backend architecture patterns, API design, database optimization, messaging, and server-side best practices for Java Spring WebFlux/MVC applications.
---

# Backend Development Patterns

Core patterns for scalable Java Spring applications. WebFlux (reactive) preferred.

## Controller Patterns

### WebFlux (Reactive)

```java
@RestController
@RequestMapping("/api/markets")
@RequiredArgsConstructor @Validated @Slf4j
public class MarketController {

    @GetMapping
    public Flux<MarketResponse> list(
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size,
            @RequestParam(required = false) MarketStatus status) {
        return marketService.findAll(page, size, status).map(mapper::toResponse);
    }

    @GetMapping("/{id}")
    public Mono<ResponseEntity<MarketResponse>> getById(@PathVariable String id) {
        return marketService.findById(id)
            .map(mapper::toResponse)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public Mono<MarketResponse> create(@Valid @RequestBody CreateMarketRequest request) {
        return marketService.create(mapper.toDomain(request)).map(mapper::toResponse);
    }

    @PutMapping("/{id}")
    public Mono<MarketResponse> update(@PathVariable String id,
                                       @Valid @RequestBody UpdateMarketRequest request) {
        return marketService.update(id, mapper.toDomain(request)).map(mapper::toResponse);
    }

    @DeleteMapping("/{id}") @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> delete(@PathVariable String id) {
        return marketService.delete(id);
    }
}
```

### Standard Response Format

```java
public record ApiResponse<T>(T data, String message, Instant timestamp) {
    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(data, "Success", Instant.now());
    }
}

public record PageResponse<T>(
    List<T> content,
    int page, int size, long totalElements, int totalPages,
    boolean first, boolean last
) {}
```

---

## Error Handling

```java
@RestControllerAdvice @Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(NotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ProblemDetail handleNotFound(NotFoundException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(WebExchangeBindException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ProblemDetail handleValidation(WebExchangeBindException ex) {
        var problem = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST);
        problem.setProperty("errors", ex.getFieldErrors().stream()
            .map(e -> Map.of("field", e.getField(), "message", e.getDefaultMessage())).toList());
        return problem;
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ProblemDetail handleAll(Exception ex) {
        log.error("Unexpected error", ex);
        return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR,
            "An unexpected error occurred");
    }
}
```

---

## Database Patterns

```java
// Avoid N+1: use JOIN or batch fetch
// BAD — N+1
marketRepository.findAll()
    .flatMap(m -> orderRepository.findByMarketId(m.id()).collectList()...);

// GOOD — JOIN in one query
databaseClient.sql("SELECT m.*, COUNT(o.id) FROM markets m LEFT JOIN orders o ...")

// GOOD — batch fetch and correlate
Flux<Market> markets = marketRepository.findAll();
Mono<Map<String, List<Order>>> orderMap = orderRepository.findByMarketIds(ids)
    .collectMultimap(Order::marketId);
Mono.zip(markets.collectList(), orderMap, (ms, om) -> /* correlate */);
```

---

## Caching (Redis)

```java
// Cache-aside with ReactiveRedisTemplate
public Mono<Market> findById(String id) {
    return redis.opsForValue().get("market:" + id)
        .switchIfEmpty(Mono.defer(() ->
            marketRepository.findById(id)
                .flatMap(m -> redis.opsForValue().set("market:" + id, m, Duration.ofMinutes(30))
                    .thenReturn(m))));
}
```

---

## Key Design Decisions

| Concern | Recommendation |
|---------|---------------|
| Controller style | WebFlux (reactive) for new services |
| Response format | RFC 7807 Problem Details for errors |
| Pagination | Cursor-based preferred over offset |
| Caching | Redis cache-aside with TTL |
| Transactions | `@Transactional` or `TransactionalOperator` |
| DB access | R2DBC for reactive, JPA only for blocking legacy |
| CQRS | Apply when reads differ significantly from writes |

---

## References

Load as needed:

- **[references/cqrs-patterns.md](references/cqrs-patterns.md)** — Full CQRS: command/query separation, command/query buses, event sourcing, domain events, projections, separate read/write repositories
- **[references/database-messaging.md](references/database-messaging.md)** — Database query optimization, transaction management, Kafka producer/consumer patterns, structured logging with MDC, Micrometer metrics, health indicators
