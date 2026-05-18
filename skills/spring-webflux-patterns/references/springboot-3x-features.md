# Spring Boot 3.x Features — Reference

## Virtual Threads (Spring Boot 3.2+, Java 21+)

```yaml
spring:
  threads:
    virtual:
      enabled: true  # enables virtual threads for request handling
```

When enabled, Spring MVC uses virtual threads for request handling. This eliminates the need for reactive stack in many I/O-bound scenarios.

**Decision matrix:**

| Scenario | Recommendation |
|----------|---------------|
| Existing WebFlux project | Keep reactive — virtual threads don't help reactive |
| New high-concurrency API with blocking I/O | Virtual threads + MVC |
| Streaming/SSE requirements | WebFlux (virtual threads don't help streams) |
| Simple CRUD with JPA | Virtual threads + MVC |
| Mixed blocking + non-blocking | WebFlux remains better |

**Rules:**
- Virtual threads are for MVC (servlet) stack only — they don't benefit WebFlux.
- Don't use `synchronized` blocks or `ThreadLocal` in virtual thread code — use `ReentrantLock` instead.
- Connection pools still need tuning — virtual threads can exhaust DB pools faster.

```java
// Adjust HikariCP pool for virtual threads
spring.datasource.hikari.maximum-pool-size=50  # may need higher than usual
```

## GraalVM Native Image

```groovy
// build.gradle
plugins {
    id 'org.graalvm.buildtools.native' version '0.10.4'
}

// Build native image
// ./gradlew nativeCompile
```

**Limitations to watch for:**
- Reflection requires `@RegisterReflectionForBinding` or `reflect-config.json`
- Runtime proxies need AOT hints (Spring handles most)
- Dynamic class loading not supported
- Startup: ~100ms (vs ~2-5s JVM); Memory: ~50MB (vs ~200MB+)

## Structured Concurrency (Preview, Java 21+)

```java
// NOT yet in Spring — experimental Java feature
// Use Reactor's Mono.zip() for similar parallel execution:
Mono.zip(
    orderService.getOrder(id),
    inventoryService.getStock(id),
    pricingService.getPrice(id)
).map(tuple -> new OrderView(tuple.getT1(), tuple.getT2(), tuple.getT3()));
```

## Spring Boot 3.x Auto-Configuration Changes

| Feature | Configuration | Notes |
|---------|--------------|-------|
| Observation API | Auto-enabled | Replaces Brave/Sleuth |
| Micrometer Tracing | `micrometer-tracing-bridge-otel` | Replaces Spring Cloud Sleuth |
| ProblemDetail | `spring.mvc.problemdetail.enabled=true` | RFC 7807 support |
| `@HttpExchange` | Declarative HTTP client | Alternative to WebClient for simple cases |

## Declarative HTTP Client (@HttpExchange)

```java
@HttpExchange(url = "/api/v1/users")
public interface UserClient {
    @GetExchange("/{id}")
    Mono<UserResponse> getUser(@PathVariable String id);

    @PostExchange
    Mono<UserResponse> createUser(@RequestBody CreateUserRequest request);
}

// Register as bean
@Bean
public UserClient userClient(WebClient.Builder builder) {
    WebClient client = builder.baseUrl("https://user-service").build();
    return HttpServiceProxyFactory.builderFor(WebClientAdapter.create(client))
        .build().createClient(UserClient.class);
}
```
