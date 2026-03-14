# Reactor Core Reference

Detailed Mono/Flux patterns, operators, backpressure, and schedulers.

## Table of Contents
- [Mono Creation](#mono-creation)
- [Flux Creation](#flux-creation)
- [Key Operators](#key-operators)
- [flatMap vs concatMap vs flatMapSequential](#flatmap-vs-concatmap-vs-flatmapsequential)
- [switchIfEmpty Patterns](#switchifempty-patterns)
- [Zip — Parallel Fetch](#zip--parallel-fetch)
- [Merge Patterns](#merge-patterns)
- [Error Handling](#error-handling)
- [Retry with Backoff](#retry-with-backoff)
- [Backpressure Strategies](#backpressure-strategies)
- [Schedulers](#schedulers)
- [Context Propagation](#context-propagation)

---

## Mono Creation

```java
Mono<String> empty = Mono.empty();
Mono<String> just = Mono.just("hello");
Mono<String> deferred = Mono.defer(() -> Mono.just(expensiveCall()));   // lazy
Mono<String> fromCallable = Mono.fromCallable(() -> blockingCall());    // lazy + blocking-safe
Mono<String> fromFuture = Mono.fromFuture(() -> asyncService.call());
Mono<Void> fromRunnable = Mono.fromRunnable(() -> sideEffect());
Mono<String> error = Mono.error(new RuntimeException("failed"));
```

## Flux Creation

```java
Flux<String> just = Flux.just("a", "b", "c");
Flux<Integer> range = Flux.range(1, 10);
Flux<Long> interval = Flux.interval(Duration.ofSeconds(1));
Flux<String> fromIterable = Flux.fromIterable(list);
Flux<String> fromStream = Flux.fromStream(() -> stream); // lazy — always use Supplier

// Generate (synchronous, 1 element per callback)
Flux<Integer> generated = Flux.generate(
    () -> 0,
    (state, sink) -> {
        sink.next(state);
        if (state >= 10) sink.complete();
        return state + 1;
    }
);

// Create (async, multi-element sink)
Flux<String> created = Flux.create(sink -> {
    eventSource.onData(sink::next);
    eventSource.onComplete(sink::complete);
    eventSource.onError(sink::error);
    sink.onDispose(() -> eventSource.close());
});
```

## Key Operators

| Operator | Purpose | Example |
|----------|---------|---------|
| `map` | Sync 1:1 transform | `.map(String::toUpperCase)` |
| `flatMap` | Async 1:N (concurrent) | `.flatMap(id -> fetchById(id))` |
| `concatMap` | Async 1:N (sequential) | `.concatMap(id -> fetchById(id))` |
| `flatMapSequential` | Async 1:N (concurrent, ordered) | `.flatMapSequential(id -> fetch(id))` |
| `filter` | Conditional filter | `.filter(u -> u.isActive())` |
| `switchIfEmpty` | Fallback when empty | `.switchIfEmpty(Mono.error(...))` |
| `defaultIfEmpty` | Default value when empty | `.defaultIfEmpty("N/A")` |
| `zip` | Combine (wait for all) | `Mono.zip(a, b, c)` |
| `then` | Ignore elements, chain next | `.then(Mono.just("done"))` |
| `thenReturn` | Ignore elements, return value | `.thenReturn("done")` |
| `doOnNext` | Side-effect on element | `.doOnNext(e -> log.info(...))` |
| `doOnError` | Side-effect on error | `.doOnError(e -> log.error(...))` |
| `doFinally` | Cleanup (any termination) | `.doFinally(signal -> cleanup())` |
| `cache` | Cache result | `.cache(Duration.ofMinutes(5))` |
| `share` | Share subscription (hot) | `.share()` |
| `collectList` | Flux → Mono<List> | `.collectList()` |
| `collectMap` | Flux → Mono<Map> | `.collectMap(Entity::getId)` |
| `delayElement` | Add delay per element | `.delayElement(Duration.ofMillis(100))` |

---

## flatMap vs concatMap vs flatMapSequential

```java
// flatMap — CONCURRENT, unordered results
// Use when: order doesn't matter, max throughput
flux.flatMap(id -> fetchById(id), 16) // concurrency = 16

// concatMap — SEQUENTIAL, ordered, one at a time
// Use when: order matters, or downstream can't handle concurrent writes
flux.concatMap(id -> fetchById(id))

// flatMapSequential — CONCURRENT execution, ORDERED results
// Use when: you want throughput AND ordering
flux.flatMapSequential(id -> fetchById(id), 8)
```

---

## switchIfEmpty Patterns

```java
// Guard against empty — always wrap fallback in Mono.defer()
public Mono<User> findByIdOrThrow(Long id) {
    return userRepository.findById(id)
        .switchIfEmpty(Mono.error(new NotFoundException("User not found: " + id)));
}

// Chain with fallback sources
public Mono<Config> getConfig(String key) {
    return cacheRepository.findByKey(key)
        .switchIfEmpty(Mono.defer(() -> dbRepository.findByKey(key)))  // ← defer prevents eager exec
        .switchIfEmpty(Mono.just(Config.defaultFor(key)));
}
```

> **Important:** Always wrap `switchIfEmpty` fallback in `Mono.defer()` if it's an eager publisher (e.g., returns `Mono.just(expensiveCall())`). Without `defer`, it executes regardless of emptiness.

---

## Zip — Parallel Fetch

```java
// Parallel independent calls — reduces latency from A+B+C to max(A,B,C)
public Mono<DashboardDto> getDashboard(Long userId) {
    return Mono.zip(
        userService.findById(userId),
        orderService.findByUserId(userId).collectList(),
        walletService.getBalance(userId)
    ).map(tuple -> new DashboardDto(tuple.getT1(), tuple.getT2(), tuple.getT3()));
}
```

---

## Merge Patterns

```java
// merge — concurrent subscriptions, interleaved results
Flux<Notification> all = Flux.merge(emailNotifications, smsNotifications, pushNotifications);

// mergeWith — instance method
Flux<Event> allEvents = internalEvents.mergeWith(externalEvents);

// mergeSequential — concurrent execution, ordered by source
Flux<Result> results = Flux.mergeSequential(source1, source2, source3);
```

---

## Error Handling

```java
// onErrorResume — replace error with fallback publisher
.onErrorResume(R2dbcException.class, ex -> cacheService.getProduct(id))

// Selective by status code
.onErrorResume(WebClientResponseException.class, ex -> {
    if (ex.getStatusCode().is4xxClientError())
        return Mono.error(new BadRequestException(ex.getResponseBodyAsString()));
    return Mono.error(new ServiceUnavailableException("Downstream error"));
})

// onErrorMap — transform error type
.onErrorMap(DataIntegrityViolationException.class,
    ex -> new DuplicateEmailException(dto.email(), ex))

// onErrorReturn — default value (use sparingly — hides errors)
.onErrorReturn(0)

// timeout with mapping
.timeout(Duration.ofSeconds(5))
.onErrorMap(TimeoutException.class, ex -> new GatewayTimeoutException("Timed out"))
```

### Global Error Handler (WebFlux)

```java
@Component
@Order(-2)
public class GlobalErrorWebExceptionHandler extends AbstractErrorWebExceptionHandler {

    public GlobalErrorWebExceptionHandler(ErrorAttributes errorAttributes,
            WebProperties.Resources resources, ApplicationContext ctx,
            ServerCodecConfigurer configurer) {
        super(errorAttributes, resources, ctx);
        setMessageWriters(configurer.getWriters());
    }

    @Override
    protected RouterFunction<ServerResponse> getRoutingFunction(ErrorAttributes attrs) {
        return RouterFunctions.route(RequestPredicates.all(), this::renderError);
    }

    private Mono<ServerResponse> renderError(ServerRequest request) {
        var error = getError(request);
        var status = determineStatus(error);
        return ServerResponse.status(status)
            .contentType(MediaType.APPLICATION_PROBLEM_JSON)
            .bodyValue(ProblemDetail.forStatusAndDetail(status, error.getMessage()));
    }

    private HttpStatus determineStatus(Throwable error) {
        if (error instanceof NotFoundException) return HttpStatus.NOT_FOUND;
        if (error instanceof BadRequestException) return HttpStatus.BAD_REQUEST;
        if (error instanceof AccessDeniedException) return HttpStatus.FORBIDDEN;
        return HttpStatus.INTERNAL_SERVER_ERROR;
    }
}
```

---

## Retry with Backoff

```java
.retryWhen(Retry.backoff(3, Duration.ofMillis(500))
    .maxBackoff(Duration.ofSeconds(5))
    .jitter(0.5)
    .filter(ex -> ex instanceof WebClientResponseException.ServiceUnavailable
               || ex instanceof ConnectException)
    .doBeforeRetry(signal -> log.warn("Retry #{}: {}", signal.totalRetries() + 1,
        signal.failure().getMessage()))
    .onRetryExhaustedThrow((spec, signal) ->
        new ServiceUnavailableException("Exhausted retries", signal.failure()))
)
```

---

## Backpressure Strategies

```java
// Buffer — store excess elements (bounded to prevent OOM)
flux.onBackpressureBuffer(1000, dropped -> log.warn("Dropped: {}", dropped),
    BufferOverflowStrategy.DROP_OLDEST);

// Drop — discard elements when downstream is slow
flux.onBackpressureDrop(dropped -> log.warn("Backpressure drop: {}", dropped));

// Latest — keep only the most recent element
flux.onBackpressureLatest();

// limitRate — request elements in batches (prefetch control)
flux.limitRate(100)          // request 100 at a time
flux.limitRate(100, 50);     // request 100, refill at 50 (low-tide)

// limitRequest — cap total elements consumed
flux.limitRequest(1000);
```

---

## Schedulers

| Scheduler | Use Case | Thread Pool |
|-----------|----------|-------------|
| `Schedulers.parallel()` | CPU-bound work | Fixed, CPU cores |
| `Schedulers.boundedElastic()` | Blocking I/O wrapping | Bounded, grows as needed |
| `Schedulers.single()` | Sequential single-threaded | Single thread |
| `Schedulers.immediate()` | Current thread | N/A |

```java
// publishOn — switch thread for DOWNSTREAM operators
flux
    .publishOn(Schedulers.parallel())
    .map(this::cpuIntensiveWork)
    .publishOn(Schedulers.boundedElastic())
    .flatMap(this::blockingIo)

// subscribeOn — switch thread for ENTIRE chain
// Only the FIRST subscribeOn takes effect
Mono.fromCallable(() -> blockingDbCall())
    .subscribeOn(Schedulers.boundedElastic())
    .map(this::transform)
```

---

## Context Propagation

```java
// Write to context
public Mono<ServerResponse> handleRequest(ServerRequest request) {
    String traceId = request.headers().firstHeader("X-Trace-Id");
    return handler.process(request)
        .contextWrite(Context.of("traceId", traceId));
}

// Read from context
public Mono<String> processWithTracing() {
    return Mono.deferContextual(ctx -> {
        String traceId = ctx.getOrDefault("traceId", "unknown");
        log.info("Processing with traceId: {}", traceId);
        return doWork();
    });
}

// WebFilter — inject for all requests
@Component
public class TraceIdWebFilter implements WebFilter {
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String traceId = Optional.ofNullable(
                exchange.getRequest().getHeaders().getFirst("X-Trace-Id"))
            .orElse(UUID.randomUUID().toString());
        exchange.getResponse().getHeaders().add("X-Trace-Id", traceId);
        return chain.filter(exchange)
            .contextWrite(Context.of("traceId", traceId));
    }
}
```

> For Spring Boot 3.x, set `spring.reactor.context-propagation=auto` and add `io.micrometer:context-propagation` dependency. MDC values propagate automatically through the reactive chain.
