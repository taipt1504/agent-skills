---
name: code-review-webflux
description: Spring WebFlux code review rules — reactive controller, R2DBC repository, transaction in WebFlux, WebClient, server setup, reactive security, error handling, pitfalls. Rule IDs WFL-*. Load when project uses WebFlux. Cite by ID in review.
globs: "*.java,*.yml"
applicability:
  always: false
  triggers:
    files_match: ["**/*Controller.java", "**/*Handler.java", "**/*Router.java", "**/*Repository.java", "**/application*.yml"]
    code_patterns: ["WebFlux", "WebClient", "RouterFunction", "@EnableWebFlux", "SecurityWebFilterChain", "R2dbcRepository", "ReactiveCrudRepository"]
    task_keywords: ["webflux", "reactive", "R2DBC", "WebClient", "Netty", "SSE"]
    related_rules:
      - rules/java/code-review-core.md
      - rules/java/code-review-reactor.md
      - rules/java/reactive.md
relevance_assessment: |
  HIGH 95%+: project uses WebFlux (verified: spring-boot-starter-webflux in build.gradle, or application.yml `web-application-type: reactive`)
  ZERO: project is pure Spring MVC (servlet)
---

# Code Review — Spring WebFlux (`WFL-*`)

> Reactive Spring stack. Load alongside `code-review-core.md` + `code-review-reactor.md`. Cite ID (`[P0][WFL-WC-002]`).

## 4.1. Controller (Reactive) (`WFL-CTL`)

### WFL-CTL-001 — Return Mono/Flux

```java
@GetMapping("/{id}")
public Mono<MerchantResponse> get(@PathVariable String id) {
    return service.findById(id).map(MerchantResponse::from);
}

@GetMapping("/stream")
public Flux<Event> stream() {
    return eventService.subscribe();
}
```

Returning sync `T` → Spring wraps in synchronous `Mono.just(T)` — defeats the point of reactive.

### WFL-CTL-002 — Flux for streaming

```java
@GetMapping(value = "/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<ServerSentEvent<Event>> sse() {
    return eventService.stream().map(e -> ServerSentEvent.builder(e).build());
}

@GetMapping(value = "/orders", produces = MediaType.APPLICATION_NDJSON_VALUE)
public Flux<Order> orders() {
    return orderService.findAll();   // streaming NDJSON
}
```

For typical list responses (JSON array), `Mono<List<T>>` is fine.

## 4.2. Reactive Repository (R2DBC) (`WFL-REP`)

### WFL-REP-001 — ReactiveCrudRepository or R2dbcRepository

```java
public interface MerchantRepository extends R2dbcRepository<Merchant, Long> {
    Mono<Merchant> findByTaxCode(String taxCode);
    Flux<Merchant> findByStatusOrderByCreatedAtDesc(Status status);
}
```

### WFL-REP-002 — @Query is native SQL

```java
@Query("SELECT * FROM merchants WHERE tax_code = :code AND status IN (:statuses)")
Flux<Merchant> search(String code, List<String> statuses);
```

R2DBC has no JPQL — queries are native SQL. Lose portability, but performance is direct and no lazy-loading magic.

### WFL-REP-003 — No lazy loading

R2DBC entity is a simple POJO, no proxy. Relationships are manual:

```java
return orderRepository.findById(id)
    .flatMap(order -> 
        itemRepository.findByOrderId(order.getId())
            .collectList()
            .map(items -> order.withItems(items)));
```

### WFL-REP-004 — Pagination

R2DBC does not auto-build `Page` like JPA — compose `Flux<T>` + `Mono<Long>` count:

```java
public Mono<Page<Merchant>> search(SearchCriteria c, Pageable pageable) {
    return repository.findBy(c, pageable)
        .collectList()
        .zipWith(repository.countBy(c))
        .map(t -> new PageImpl<>(t.getT1(), pageable, t.getT2()));
}
```

## 4.3. Transaction in WebFlux (`WFL-TX`)

### WFL-TX-001 — @Transactional works with R2dbcTransactionManager

Spring Boot autoconfigures it when R2DBC driver is present. Subscription-bound (not thread-bound). Method must return Mono/Flux.

```java
@Transactional
public Mono<Order> place(Order order) {
    return repository.save(order)
        .flatMap(saved -> publishEvent(saved).thenReturn(saved));
}
```

### WFL-TX-002 — Do not mix JDBC and R2DBC in same TX

```java
@Transactional
public Mono<Void> bad() {
    return r2dbcRepo.save(a)
        .then(Mono.fromRunnable(() -> jdbcRepo.save(b)));   // ❌ different manager
}
```

Two transaction managers, no shared TX → dual-write problem. Pick one stack.

### WFL-TX-003 — TransactionalOperator for programmatic TX

```java
private final TransactionalOperator tx;

public Mono<Order> create(Order order) {
    return tx.transactional(
        repository.save(order)
            .then(outboxRepo.save(event))
            .thenReturn(order)
    );
}
```

Useful when `@Transactional` annotation doesn't fit (e.g., factory methods).

## 4.4. WebClient (`WFL-WC`)

### WFL-WC-001 — WebClient, not RestTemplate

RestTemplate is blocking → blocks event loop in WebFlux. WebClient is reactive-native.

```java
@Bean
public WebClient paymentClient(WebClient.Builder builder, PaymentProperties props) {
    return builder
        .baseUrl(props.url())
        .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
        .clientConnector(new ReactorClientHttpConnector(
            HttpClient.create()
                .responseTimeout(Duration.ofSeconds(10))
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5000)
        ))
        .build();
}
```

### WFL-WC-002 — Configure timeouts explicitly

Timeout EVERY phase: connect, read, write, response. Default is often infinite → hang forever.

```java
HttpClient.create()
    .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5000)
    .responseTimeout(Duration.ofSeconds(10))
    .doOnConnected(c -> c
        .addHandlerLast(new ReadTimeoutHandler(10))
        .addHandlerLast(new WriteTimeoutHandler(10))
    );
```

### WFL-WC-003 — Retry with backoff

```java
webClient.post()
    .uri("/charge")
    .bodyValue(req)
    .retrieve()
    .bodyToMono(Result.class)
    .retryWhen(Retry.backoff(3, Duration.ofMillis(500))
        .filter(this::isRetryable)
        .onRetryExhaustedThrow((spec, signal) -> signal.failure())
    );
```

Idempotent operations only. Non-idempotent (POST create) → require idempotency key.

### WFL-WC-004 — Circuit breaker for external calls

Resilience4j integrates with WebFlux:

```java
return webClient.get().uri("/x")
    .retrieve().bodyToMono(X.class)
    .transformDeferred(CircuitBreakerOperator.of(circuitBreaker))
    .transformDeferred(TimeLimiterOperator.of(timeLimiter))
    .onErrorResume(CallNotPermittedException.class, e -> fallback());
```

Prevents cascade failure when dependency is down.

### WFL-WC-005 — Error handling

```java
webClient.get().uri("/x")
    .retrieve()
    .onStatus(HttpStatus::is4xxClientError, response ->
        response.bodyToMono(ErrorBody.class)
            .flatMap(err -> Mono.error(new ClientException(err))))
    .onStatus(HttpStatus::is5xxServerError, response ->
        Mono.error(new ServerException()))
    .bodyToMono(X.class);
```

Default `retrieve()` throws `WebClientResponseException` for 4xx/5xx — wrap as business exception.

## 4.5. Server Setup (`WFL-SRV`)

### WFL-SRV-001 — Netty default

```yaml
spring:
  main:
    web-application-type: reactive
server:
  netty:
    connection-timeout: 10s
    idle-timeout: 60s
```

Do not deploy WebFlux on Tomcat/Jetty unless legacy reason. Netty is the sweet spot.

### WFL-SRV-002 — R2DBC pool config

```yaml
spring:
  r2dbc:
    pool:
      initial-size: 10
      max-size: 50
      max-acquire-time: 5s     # ✅ prevents hang when pool full
      max-idle-time: 30m
      max-life-time: 1h
      validation-query: SELECT 1
```

`max-acquire-time` is critical — without it, requests wait indefinitely when overloaded.

## 4.6. Security (Reactive) (`WFL-SEC`)

### WFL-SEC-001 — @EnableWebFluxSecurity

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
public class SecurityConfig {
    @Bean
    public SecurityWebFilterChain filterChain(ServerHttpSecurity http) {
        return http
            .csrf(ServerHttpSecurity.CsrfSpec::disable)
            .authorizeExchange(ex -> ex
                .pathMatchers("/actuator/health").permitAll()
                .pathMatchers("/api/**").authenticated())
            .oauth2ResourceServer(oauth -> oauth.jwt(Customizer.withDefaults()))
            .build();
    }
}
```

Do NOT use `WebSecurityConfigurerAdapter` (servlet-only, deprecated).

### WFL-SEC-002 — ReactiveSecurityContextHolder

```java
return ReactiveSecurityContextHolder.getContext()
    .map(ctx -> ctx.getAuthentication().getName())
    .flatMap(username -> service.loadByUsername(username));
```

## 4.7. Error Handling (WebFlux) (`WFL-EXC`)

### WFL-EXC-001 — @RestControllerAdvice returns Mono

```java
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(BusinessException.class)
    public Mono<ResponseEntity<ErrorResponse>> handle(BusinessException e) {
        return Mono.just(ResponseEntity
            .status(e.code().status())
            .body(new ErrorResponse(e.code().name(), e.getMessage())));
    }
}
```

### WFL-EXC-002 — Custom ErrorWebExceptionHandler

For lower-level errors (filter exceptions, content negotiation):

```java
@Component
@Order(-2)   // before DefaultErrorWebExceptionHandler
public class GlobalErrorHandler implements ErrorWebExceptionHandler {
    @Override
    public Mono<Void> handle(ServerWebExchange exchange, Throwable e) { ... }
}
```

## 4.8. WebFlux Pitfalls (`WFL-PIT`)

### WFL-PIT-001 — Filter order

```java
@Component
@Order(1)   // ✅ explicit order
public class TracingFilter implements WebFilter { ... }
```

Multiple filters → behavior depends on order. Use `@Order` or implement `Ordered`.

### WFL-PIT-002 — Backpressure

`Flux<T>` from R2DBC has natural backpressure. From Kafka, configure `KafkaReceiver` concurrency correctly.

Infinite sources require a boundary:
```java
flux.take(Duration.ofMinutes(5))
flux.take(1000)
flux.timeout(Duration.ofSeconds(30))
```

### WFL-PIT-003 — DataBuffer leak

When consuming `DataBuffer` manually:
```java
return exchange.getRequest().getBody()
    .map(buffer -> {
        try {
            return parse(buffer);
        } finally {
            DataBufferUtils.release(buffer);   // ✅ must release
        }
    });
```

Forgetting to release → off-heap memory leak.

### WFL-PIT-004 — Request body can be subscribed only once

To log the request body → buffer + replay:

```java
DataBufferUtils.join(request.getBody())
    .flatMap(buffer -> {
        byte[] bytes = new byte[buffer.readableByteCount()];
        buffer.read(bytes);
        DataBufferUtils.release(buffer);
        log.info("body={}", new String(bytes));
        
        ServerHttpRequest decorated = new ServerHttpRequestDecorator(request) {
            @Override public Flux<DataBuffer> getBody() {
                return Flux.just(exchange.getResponse().bufferFactory().wrap(bytes));
            }
        };
        return chain.filter(exchange.mutate().request(decorated).build());
    });
```

## Related

- `rules/java/code-review-core.md` — CORE-* foundation rules
- `rules/java/code-review-reactor.md` — RX-* Reactor fundamentals (prerequisite)
- `rules/java/code-review-crosscut.md` — XCT-* + PR checklist + severity
- `rules/java/reactive.md` — no-`.block()` hard block
- `skills/spring-webflux-patterns` — WebFlux implementation patterns
