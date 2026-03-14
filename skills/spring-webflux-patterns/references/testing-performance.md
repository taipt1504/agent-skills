# Testing & Performance Reference

StepVerifier, WebTestClient, PublisherProbe, performance tuning, and anti-patterns.

## Table of Contents
- [StepVerifier — All Scenarios](#stepverifier--all-scenarios)
- [WebTestClient](#webtestclient)
- [PublisherProbe (Verifying Side Effects)](#publisherprobe-verifying-side-effects)
- [Testing with Testcontainers + R2DBC](#testing-with-testcontainers--r2dbc)
- [Performance Tuning](#performance-tuning)
- [Anti-Patterns to Avoid](#anti-patterns-to-avoid)

---

## StepVerifier — All Scenarios

```java
// Basic Mono
StepVerifier.create(userService.findById(1L))
    .expectNextMatches(user -> user.email().equals("alice@example.com"))
    .verifyComplete();

// Basic Flux
StepVerifier.create(userService.findAll())
    .expectNextCount(5)
    .verifyComplete();

// Ordered elements
StepVerifier.create(Flux.just("a", "b", "c"))
    .expectNext("a", "b", "c")
    .verifyComplete();

// Error assertion
StepVerifier.create(userService.findById(999L))
    .expectError(NotFoundException.class)
    .verify();

// Error message
StepVerifier.create(userService.findById(999L))
    .expectErrorMessage("User not found: 999")
    .verify();

// Error satisfies
StepVerifier.create(userService.findById(999L))
    .expectErrorSatisfies(ex -> assertThat(ex)
        .isInstanceOf(NotFoundException.class)
        .hasMessage("User not found: 999"))
    .verify();

// Time-based with VirtualTimeScheduler (don't use Thread.sleep!)
StepVerifier.withVirtualTime(() -> Flux.interval(Duration.ofSeconds(1)).take(3))
    .expectSubscription()
    .thenAwait(Duration.ofSeconds(3))
    .expectNextCount(3)
    .verifyComplete();

// With timeout (CI-safe)
StepVerifier.create(asyncOperation())
    .expectNextCount(1)
    .verifyComplete(Duration.ofSeconds(5));

// Consume context
StepVerifier.create(
    Mono.deferContextual(ctx -> Mono.just(ctx.get("traceId")))
        .contextWrite(Context.of("traceId", "abc-123"))
)
    .expectNext("abc-123")
    .verifyComplete();

// Record all and assert
StepVerifier.create(Flux.range(1, 100).filter(n -> n % 2 == 0))
    .recordWith(ArrayList::new)
    .thenConsumeWhile(n -> true)
    .consumeRecordedWith(list -> assertThat(list).hasSize(50).containsOnly(/* evens */))
    .verifyComplete();
```

---

## WebTestClient

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UserControllerTest {

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void shouldReturnUser() {
        webTestClient.get()
            .uri("/api/users/1")
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus().isOk()
            .expectBody(UserResponse.class)
            .value(user -> assertThat(user.email()).isEqualTo("alice@example.com"));
    }

    @Test
    void shouldCreateUser() {
        var request = new CreateUserRequest("bob@example.com", "Bob");
        webTestClient.post()
            .uri("/api/users")
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectHeader().exists("Location")
            .expectBody()
            .jsonPath("$.email").isEqualTo("bob@example.com");
    }

    @Test
    void shouldReturn404WhenNotFound() {
        webTestClient.get()
            .uri("/api/users/999")
            .exchange()
            .expectStatus().isNotFound();
    }

    @Test
    void shouldStreamEvents() {
        webTestClient.get()
            .uri("/api/users/stream")
            .accept(MediaType.TEXT_EVENT_STREAM)
            .exchange()
            .expectStatus().isOk()
            .returnResult(UserEvent.class)
            .getResponseBody()
            .take(3)
            .as(StepVerifier::create)
            .expectNextCount(3)
            .thenCancel()
            .verify();
    }

    // Bind to controller directly (no server, faster)
    @Test
    void unitTestController() {
        WebTestClient client = WebTestClient
            .bindToController(new UserController(mockUserService))
            .build();

        client.get().uri("/api/users/1").exchange().expectStatus().isOk();
    }
}
```

---

## PublisherProbe (Verifying Side Effects)

Use when testing that a branch/fallback is actually subscribed to.

```java
@Test
void shouldSendNotificationOnConfirm() {
    var notificationProbe = PublisherProbe.empty(); // acts as Mono<Void>

    when(notificationPort.sendOrderConfirmation(any(), any()))
        .thenReturn(notificationProbe.mono());

    StepVerifier.create(orderService.createOrder(validCommand()))
        .expectNextMatches(r -> r.status() == OrderStatus.CONFIRMED)
        .verifyComplete();

    notificationProbe.assertWasSubscribed();  // ← verification
    notificationProbe.assertWasNotCancelled();
}

@Test
void shouldFallbackToDatabase() {
    var cacheProbe = PublisherProbe.empty();
    var dbProbe = PublisherProbe.of(Mono.just(cachedUser));

    when(cacheRepo.findByKey("config")).thenReturn(cacheProbe.mono()); // empty
    when(dbRepo.findByKey("config")).thenReturn(dbProbe.mono());

    StepVerifier.create(configService.getConfig("config"))
        .expectNextCount(1)
        .verifyComplete();

    cacheProbe.assertWasSubscribed();
    dbProbe.assertWasSubscribed();
}
```

---

## Testing with Testcontainers + R2DBC

```java
@DataR2dbcTest
@Testcontainers
class UserRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () ->
            "r2dbc:postgresql://" + postgres.getHost() + ":" + postgres.getMappedPort(5432) + "/testdb");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.flyway.url", postgres::getJdbcUrl);
    }

    @Autowired
    private UserRepository userRepository;

    @Test
    void shouldSaveAndFind() {
        var entity = new UserEntity(null, "alice@example.com", "Alice", "ACTIVE", Instant.now(), null);
        StepVerifier.create(userRepository.save(entity)
            .flatMap(saved -> userRepository.findById(saved.getId())))
            .expectNextMatches(u -> u.email().equals("alice@example.com"))
            .verifyComplete();
    }
}
```

---

## Performance Tuning

### Netty Tuning (application.yml)

```yaml
server:
  netty:
    connection-timeout: 10s
    max-keep-alive-requests: 10000
    idle-timeout: 60s

spring:
  r2dbc:
    pool:
      initial-size: 10
      max-size: 50
      max-idle-time: 30m
      max-acquire-time: 10s
      validation-query: SELECT 1
  reactor:
    context-propagation: auto  # Spring Boot 3.x — propagates MDC automatically
```

### JVM Flags (container)

```
-XX:+UseG1GC -XX:MaxGCPauseMillis=100
-XX:+UseStringDeduplication
-Dreactor.netty.ioWorkerCount=8    # default: 2 * cores, rarely needs tuning
-Dreactor.schedulers.defaultPoolSize=8  # boundedElastic
```

### Profiling Checklist

- [ ] No `block()` calls on event loop threads — use `subscribeOn(boundedElastic())`
- [ ] Connection pool sized correctly — monitor active/pending via Micrometer
- [ ] `flatMap` concurrency set appropriately (default 256 — may be too high)
- [ ] `limitRate()` on high-throughput Flux to control prefetch
- [ ] `cache()` on expensive Mono that's subscribed multiple times

---

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `block()` on event loop | Deadlock | Move to `boundedElastic()` via `subscribeOn` |
| `Mono.just(expensiveCall())` | Eager execution, no lazy | `Mono.fromCallable(() -> expensiveCall())` |
| `.switchIfEmpty(service.call())` | Eager fallback execution | `.switchIfEmpty(Mono.defer(() -> service.call()))` |
| Returning `null` from `.map()` | NullPointerException | Return empty object or use `.flatMap()` + `Mono.empty()` |
| Ignoring publisher (no subscribe) | Nothing executes | Chain all publishers, subscribe at edge |
| `Thread.sleep()` in tests | Flaky, slow | `StepVerifier.withVirtualTime()` |
| Mutable shared state in operators | Race conditions | Use immutable objects, `Sinks` for shared state |
| `.toFuture().get()` | Blocks thread | Use reactive pipeline all the way |
| `forEach` on `Flux` | Breaks pipeline | `.subscribe()` or `.collectList().block()` only at edges |
| Not setting `maxInMemorySize` | `DataBufferLimitException` | Set in `WebClient` codecs config |

### Blocking Code Wrapper (Only When Necessary)

```java
// Wrap legacy blocking library correctly
public Mono<Result> callLegacyLibrary(String param) {
    return Mono.fromCallable(() -> legacyBlockingClient.call(param))
        .subscribeOn(Schedulers.boundedElastic());  // offloads to non-event-loop thread
}

// DO NOT do this — blocks event loop
public Mono<Result> wrongApproach(String param) {
    return Mono.just(legacyBlockingClient.call(param));  // executes eagerly on current thread
}
```
