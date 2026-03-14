---
name: spring-webflux-patterns
description: >
  Spring WebFlux patterns for reactive backend development.
  Covers Project Reactor, reactive chains, error handling, R2DBC, WebClient, SSE,
  backpressure, schedulers, context propagation, reactive security, and testing.
  Use when building non-blocking reactive APIs with Spring Boot 3.x and Java 17+.
---

# Spring WebFlux Patterns

Production-ready reactive patterns for Java 17+ / Spring Boot 3.x.

## Dependencies

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webflux</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-r2dbc</artifactId>
</dependency>
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>r2dbc-postgresql</artifactId>
    <scope>runtime</scope>
</dependency>
<dependency>
    <groupId>io.r2dbc</groupId>
    <artifactId>r2dbc-pool</artifactId>
</dependency>
<dependency>
    <groupId>io.projectreactor</groupId>
    <artifactId>reactor-test</artifactId>
    <scope>test</scope>
</dependency>
```

## Key Operators

| Operator | Purpose |
|----------|---------|
| `map` | Sync 1:1 transform |
| `flatMap` | Async 1:N (concurrent) |
| `concatMap` | Async 1:N (sequential, ordered) |
| `flatMapSequential` | Concurrent execution, ordered results |
| `switchIfEmpty` | Fallback when empty |
| `Mono.zip` | Combine publishers (parallel fetch) |
| `onErrorResume` | Replace error with fallback publisher |
| `onErrorMap` | Transform error type |
| `retryWhen` | Retry with backoff |
| `doOnNext` | Side-effect on element |
| `cache` | Cache result for reuse |
| `publishOn` | Switch thread for downstream operators |
| `subscribeOn` | Switch thread for entire chain |

## Common Patterns

### Parallel Fetch (Zip)

```java
return Mono.zip(userService.findById(userId), orderService.findByUserId(userId).collectList())
    .map(tuple -> new DashboardDto(tuple.getT1(), tuple.getT2()));
```

### switchIfEmpty + Defer (Cache-Miss Pattern)

```java
return cacheRepository.findByKey(key)
    .switchIfEmpty(Mono.defer(() -> dbRepository.findByKey(key)))  // ⚠️ always Mono.defer()
    .switchIfEmpty(Mono.error(new NotFoundException("Not found: " + key)));
```

### Retry with Backoff

```java
.retryWhen(Retry.backoff(3, Duration.ofMillis(500))
    .maxBackoff(Duration.ofSeconds(5))
    .jitter(0.5)
    .filter(ex -> ex instanceof ConnectException))
```

### Wrap Blocking Code

```java
Mono.fromCallable(() -> legacyClient.blockingCall(id))
    .subscribeOn(Schedulers.boundedElastic())  // ✅ never block Netty thread
```

### Reactive Transaction

```java
@Transactional  // declarative
public Mono<OrderDto> createOrder(CreateOrderRequest request) { ... }

// Or programmatic:
return pipeline.as(txOperator::transactional);
```

### Error Handling

```java
.onErrorResume(R2dbcException.class, ex -> cacheService.getProduct(id))  // fallback
.onErrorMap(DataIntegrityViolationException.class,
    ex -> new DuplicateEmailException(dto.email(), ex))                   // remap
.timeout(Duration.ofSeconds(5))
.onErrorMap(TimeoutException.class, ex -> new GatewayTimeoutException())
```

## Schedulers

| Scheduler | Use Case |
|-----------|----------|
| `Schedulers.parallel()` | CPU-bound work |
| `Schedulers.boundedElastic()` | Blocking I/O wrapping |
| `Schedulers.single()` | Sequential, single-threaded |

```java
// publishOn — switches thread for DOWNSTREAM operators
flux.publishOn(Schedulers.boundedElastic()).flatMap(this::blockingIo)

// subscribeOn — switches thread for ENTIRE chain
Mono.fromCallable(() -> blockingCall()).subscribeOn(Schedulers.boundedElastic())
```

## Anti-Patterns (Must Avoid)

```java
// ❌ NEVER — blocks Netty event loop
User user = userService.findById(id).block();

// ❌ Fire-and-forget loses errors
auditService.log(order).subscribe();  // use .then() or doOnSuccess

// ❌ Eager evaluation
return Mono.just(expensiveCall());   // use Mono.defer(() -> Mono.just(...))

// ❌ Thread.sleep in reactive chain
Thread.sleep(1000);                  // use .delayElement(Duration.ofSeconds(1))

// ❌ Ignoring return values
userRepository.deleteById(id);       // returns Mono<Void>, must be subscribed
```

## R2DBC Pool (application.yml)

```yaml
spring:
  r2dbc:
    url: r2dbc:pool:postgresql://localhost:5432/mydb
    pool:
      initial-size: 10
      max-size: 50
      max-idle-time: 30m
      max-life-time: 60m
      validation-query: SELECT 1
```

## Checklist

- [ ] No `.block()` in WebFlux code paths
- [ ] Blocking code wrapped with `Schedulers.boundedElastic()`
- [ ] `switchIfEmpty` fallbacks wrapped in `Mono.defer()`
- [ ] Retry with backoff on all WebClient calls
- [ ] Timeouts on all external calls
- [ ] R2DBC pool configured (`max-size`, `max-idle-time`)
- [ ] StepVerifier tests for all service methods
- [ ] WebTestClient integration tests for all endpoints

## References

Load as needed:

- **[references/reactor-core.md](references/reactor-core.md)** — Mono/Flux creation, all operators, flatMap vs concatMap, backpressure strategies
- **[references/controllers-r2dbc.md](references/controllers-r2dbc.md)** — Annotated controllers, router functions, R2DBC repository + complex queries, transactions
- **[references/webclient-security.md](references/webclient-security.md)** — WebClient config/usage/SSE, context propagation, reactive Spring Security
- **[references/testing-performance.md](references/testing-performance.md)** — StepVerifier, WebTestClient, PublisherProbe, Netty tuning, migration guide, anti-patterns
