---
name: spring-webflux-patterns
description: Reactive Spring stack patterns — Mono/Flux operator chains, WebClient, WebFilter, R2DBC, StepVerifier, WebTestClient, SSE, backpressure. Project must use Spring WebFlux (non-blocking, event-loop). Mutually exclusive with spring-mvc-patterns.
triggers:
  natural: ["reactive endpoint", "mono flux chain", "webclient", "webflux test", "sse stream"]
  code: ["Mono", "Flux", "WebClient", "RouterFunction", "@EnableWebFlux", "ReactiveCrudRepository"]
applicability:
  always: false
  triggers:
    files_match: ["**/*Controller.java", "**/*Handler.java", "**/*Router.java", "**/application*.yml"]
    code_patterns: ["Mono<", "Flux<", "WebClient", "RouterFunction", "ServerHttpSecurity", "ReactiveCrudRepository", "R2dbc"]
    task_keywords: ["webflux", "reactive", "Mono", "Flux", "non-blocking", "R2DBC", "backpressure"]
    related_rules:
      - rules/java/reactive.md
      - rules/java/api-design.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 90%+: project uses WebFlux (verified: spring-boot-starter-webflux in build.gradle, or `spring.main.web-application-type: reactive`)
  HIGH 80%+: task adds reactive endpoint OR consumes/produces Mono/Flux
  MEDIUM 40-79%: task touches reactive infrastructure (security filter, WebFilter, R2DBC)
  LOW 1-39%: task tangentially related (e.g., DTO that crosses reactive boundary)
  ZERO: project uses Spring MVC (servlet stack); verify in application.yml
---

# Spring WebFlux Patterns — Reactive Stack

## Stack constraint

WebFlux requires non-blocking end-to-end. NEVER mix with servlet stack. Verify:
- `spring-boot-starter-webflux` on classpath (no `spring-boot-starter-web`)
- `spring.main.web-application-type: reactive` (or default if only webflux)
- All I/O reactive: R2DBC (not JDBC/JPA), Lettuce (not Jedis), reactor-kafka (not spring-kafka blocking consumer)

## Controller pattern

```java
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
@Validated
public class OrderController {
    private final CreateOrderUseCase createOrderUseCase;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<OrderResponse> createOrder(@Valid @RequestBody CreateOrderRequest request) {
        return createOrderUseCase.execute(request);
    }

    @GetMapping
    public Flux<OrderDto> list(@RequestParam(defaultValue = "20") @Max(100) int size) {
        return orderQueryService.findAll(size);
    }
}
```

**Rules:** `@RequiredArgsConstructor`, `@Valid` on request bodies, return DTOs (never entities), use case objects for logic.

## Reactive operator discipline

- NEVER `.block()` in src/main/. Wrap blocking with `Schedulers.boundedElastic()`.
- `switchIfEmpty(Mono.defer(...))` for fallbacks — without `defer`, alternative evaluates eagerly.
- `flatMap` = concurrent. `concatMap` = sequential. `flatMapSequential` = concurrent + ordered.
- `Mono.fromCallable(blockingCode).subscribeOn(Schedulers.boundedElastic())` for unavoidable blocking.
- `.doOnError(e -> log.error("...", e))` before `onErrorResume` / `onErrorMap`.

## R2DBC transactions

```java
@RequiredArgsConstructor
public class OrderService {
    private final OrderRepository repo;
    private final TransactionalOperator txOp;

    public Mono<Order> placeOrder(Order order) {
        return repo.save(order)
            .flatMap(saved -> publishEvent(saved).thenReturn(saved))
            .as(txOp::transactional);
    }
}
```

Use `TransactionalOperator` for explicit, composable transactions. `@Transactional` works but harder to compose in operator chains.

## WebFilter (cross-cutting)

```java
@Component
public class TracingFilter implements WebFilter {
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String requestId = exchange.getRequest().getHeaders().getFirst("X-Request-Id");
        return chain.filter(exchange)
            .contextWrite(Context.of("requestId", requestId != null ? requestId : UUID.randomUUID().toString()));
    }
}
```

Context propagation via Reactor Context (not ThreadLocal — lost across operator boundaries).

## Security filter

Reactive security via `SecurityWebFilterChain` (NOT `SecurityFilterChain`):

```java
@Bean
public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
    return http
        .authorizeExchange(auth -> auth
            .pathMatchers("/actuator/health").permitAll()
            .anyExchange().authenticated())
        .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()))
        .build();
}
```

Method security: `@EnableReactiveMethodSecurity`. See `spring-security` skill for full patterns.

## Testing

- `WebTestClient` for endpoint tests
- `StepVerifier` for `Mono`/`Flux` assertions
- `VirtualTimeScheduler` for time-based operators (`delay`, `interval`)
- `.expectNoEvent(Duration)` to assert silence

```java
@Test
void shouldReturnOrderWhenIdExists() {
    webTestClient.get().uri("/api/v1/orders/{id}", "abc")
        .exchange()
        .expectStatus().isOk()
        .expectBody(OrderResponse.class)
        .value(r -> assertThat(r.id()).isEqualTo("abc"));
}
```

## Server-Sent Events

```java
@GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<OrderEvent> streamOrders() {
    return orderEventService.stream()
        .onBackpressureBuffer(1000, BufferOverflowStrategy.DROP_OLDEST);
}
```

## Anti-patterns

| Anti-pattern | Fix |
|---|---|
| `.block()` in reactive code | Chain operators or `subscribeOn(boundedElastic())` |
| `JpaRepository` in reactive chain | Use `ReactiveCrudRepository` / R2DBC |
| `Mono.just(expensiveCall())` | `Mono.defer()` or `Mono.fromCallable()` |
| Fire-and-forget `.subscribe()` in handler | Return `.then()` or use `doOnSuccess` |
| `switchIfEmpty(Mono.error(...))` without `defer` | Wrap in `Mono.defer(() -> Mono.error(...))` |
| `ThreadLocal` for context | Reactor `Context` via `contextWrite` / `deferContextual` |
| `@Transactional` on async returning method | Use `TransactionalOperator` |
| Unbounded `.onBackpressureBuffer()` | Bounded buffer or `onBackpressureDrop` |

## Verification checklist

- [ ] `@RequiredArgsConstructor` (no `@Autowired`)
- [ ] `@Valid` on request bodies
- [ ] DTOs returned (never entities)
- [ ] No `.block()` in src/main/
- [ ] R2DBC (not JPA) for relational
- [ ] StepVerifier + WebTestClient tests
- [ ] Timeouts on all `WebClient` calls
- [ ] Bounded backpressure on `Flux` sources
- [ ] Graceful shutdown + actuator configured

## References

- **[references/spring-webflux.md](references/spring-webflux.md)** — Full operator catalog, R2DBC, WebClient, SSE, StepVerifier, WebTestClient
- **[references/springboot-production.md](references/springboot-production.md)** — Caching, async, rate limiting, Jackson, R2DBC pool, graceful shutdown, actuator
- **[references/springboot-3x-features.md](references/springboot-3x-features.md)** — Virtual threads (3.2+), GraalVM native, `@HttpExchange`, Observation API

## Related

- `rules/java/reactive.md` — no-.block() mandate, backpressure, scheduler discipline
- `skills/spring-security` — `SecurityWebFilterChain`
- `skills/database-patterns` — R2DBC repository patterns
- `skills/api-design` — REST conventions, RFC 7807
- `skills/testing-workflow` — WebTestClient + StepVerifier
