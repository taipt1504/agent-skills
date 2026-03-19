---
name: spring-patterns
description: >
  Unified Spring MVC and WebFlux patterns for Java 17+ / Spring Boot 3.x.
  Covers controllers, handlers, WebClient, filters, interceptors, pagination,
  caching, async processing, rate limiting, and production defaults.
  Activates for both servlet (MVC) and reactive (WebFlux) stacks.
triggers:
  - Spring MVC controllers or RestController annotations
  - Spring WebFlux handlers or router functions
  - WebClient configuration or usage
  - Servlet filters or WebFlux WebFilter
  - HandlerInterceptor implementations
  - Pagination (Page, Slice, cursor-based)
  - Spring caching (@Cacheable, @CacheEvict)
  - R2DBC repositories or DatabaseClient
  - SSE endpoints or Sinks
  - StepVerifier or WebTestClient usage
---

# Spring Patterns

## Stack Decision Table

| Criteria | MVC (Servlet) | WebFlux (Reactive) |
|----------|---------------|---------------------|
| I/O model | Blocking, 1 thread/request | Non-blocking, event loop |
| Database | JPA/Hibernate (JDBC) | R2DBC |
| Throughput | Moderate (<1K concurrent) | High (>1K concurrent) |
| Libraries | Most Java libs (blocking OK) | Must be reactive end-to-end |
| Testing | MockMvc | WebTestClient + StepVerifier |
| Use when | CRUD apps, team new to reactive | High-concurrency, streaming, SSE |

**Rule:** Never mix stacks. If WebFlux dependency is on classpath, ALL code must be non-blocking.

## Controller Pattern (Both Stacks)

```java
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
@Validated
public class OrderController {
    private final CreateOrderUseCase createOrderUseCase;

    // MVC: returns ResponseEntity<T> / T
    // WebFlux: returns Mono<T> / Flux<T>

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public /* Mono<OrderResponse> or OrderResponse */
        createOrder(@Valid @RequestBody CreateOrderRequest request) { ... }
}
```

**Rules:** `@RequiredArgsConstructor` (no `@Autowired`), `@Valid` on request bodies, return DTOs (never entities), use case objects for business logic.

## IF MVC

- `OncePerRequestFilter` for request logging (MDC + requestId)
- `HandlerInterceptor` for rate limiting, auth checks
- `@WebMvcTest` + `MockMvc` for controller tests
- `SecurityFilterChain` via `HttpSecurity`
- `Page<T>` (offset) or `Slice<T>` (cursor) for pagination

## IF WebFlux

- **Never** `.block()` -- wrap blocking code with `Schedulers.boundedElastic()`
- `switchIfEmpty` fallbacks **must** use `Mono.defer()`
- `flatMap` (concurrent) vs `concatMap` (sequential) vs `flatMapSequential` (concurrent+ordered)
- `WebFilter` for cross-cutting (tracing, auth)
- `StepVerifier` for all reactive tests; `WebTestClient` for endpoints
- `@Transactional` or `TransactionalOperator` for R2DBC transactions

## Production Defaults (Both)

- Jackson: `non_null`, `write-dates-as-timestamps: false`, `fail-on-unknown-properties: true`
- Graceful shutdown: `server.shutdown: graceful`
- Actuator: expose `health,info,metrics,prometheus`
- `@Transactional(readOnly = true)` on query methods
- Rate limiting on write endpoints (Resilience4j or Redis interceptor)
- Connection pool tuning: HikariCP (MVC) or R2DBC pool (WebFlux)

## Anti-Patterns

| Anti-Pattern | Fix |
|---|---|
| `.block()` in reactive code | Chain operators or `subscribeOn(boundedElastic())` |
| `@Autowired` field injection | `@RequiredArgsConstructor` |
| Entities in API responses | Map to DTOs |
| `spring.jpa.open-in-view: true` | Set to `false` |
| `Mono.just(expensiveCall())` | `Mono.defer()` or `Mono.fromCallable()` |
| Fire-and-forget `.subscribe()` | Use `.then()` or `doOnSuccess` |

## Verification Checklist

- [ ] Constructor injection only (`@RequiredArgsConstructor`)
- [ ] `@Valid` on all request bodies, `@Validated` on controller class
- [ ] DTOs returned (never entities)
- [ ] Pagination capped (`@Max(100)` on size)
- [ ] `@Transactional(readOnly = true)` on queries
- [ ] No `.block()` in reactive paths
- [ ] StepVerifier tests (WebFlux) or MockMvc tests (MVC)
- [ ] Timeouts + retry on all external calls
- [ ] Graceful shutdown + actuator configured

## References

Load as needed for full patterns and code examples:

- **[references/spring-mvc.md](references/spring-mvc.md)** -- Controllers, MockMvc testing, filters, interceptors, pagination, security config
- **[references/spring-webflux.md](references/spring-webflux.md)** -- Reactive chains, operators, R2DBC, WebClient, SSE, StepVerifier, WebTestClient
- **[references/springboot-production.md](references/springboot-production.md)** -- Caching, async, rate limiting, Jackson, HikariCP, graceful shutdown, actuator
