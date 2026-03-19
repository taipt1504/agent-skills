# Spring WebFlux Patterns Reference

Full reactive patterns for Java 17+ / Spring Boot 3.x with Project Reactor.

## Table of Contents
- [Dependencies](#dependencies)
- [Mono/Flux Creation](#monoflux-creation)
- [Key Operators](#key-operators)
- [flatMap vs concatMap vs flatMapSequential](#flatmap-vs-concatmap-vs-flatmapsequential)
- [Common Reactive Patterns](#common-reactive-patterns)
- [Error Handling](#error-handling)
- [Backpressure Strategies](#backpressure-strategies)
- [Schedulers](#schedulers)
- [Context Propagation](#context-propagation)
- [Annotated Controllers](#annotated-controllers)
- [Router Functions](#router-functions)
- [R2DBC Repository](#r2dbc-repository)
- [R2DBC DatabaseClient](#r2dbc-databaseclient)
- [Reactive Transactions](#reactive-transactions)
- [WebClient Configuration](#webclient-configuration)
- [WebClient Usage](#webclient-usage)
- [SSE with Sinks](#sse-with-sinks)
- [Reactive Spring Security](#reactive-spring-security)
- [StepVerifier Testing](#stepverifier-testing)
- [WebTestClient Testing](#webtestclient-testing)
- [PublisherProbe](#publisherprobe)
- [Testcontainers + R2DBC](#testcontainers--r2dbc)
- [Performance Tuning](#performance-tuning)
- [Anti-Patterns](#anti-patterns)

---

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

---

## Mono/Flux Creation

```java
// Mono
Mono<String> empty = Mono.empty();
Mono<String> just = Mono.just("hello");
Mono<String> deferred = Mono.defer(() -> Mono.just(expensiveCall()));
Mono<String> fromCallable = Mono.fromCallable(() -> blockingCall());
Mono<String> fromFuture = Mono.fromFuture(() -> asyncService.call());
Mono<Void> fromRunnable = Mono.fromRunnable(() -> sideEffect());
Mono<String> error = Mono.error(new RuntimeException("failed"));

// Flux
Flux<String> just = Flux.just("a", "b", "c");
Flux<Integer> range = Flux.range(1, 10);
Flux<Long> interval = Flux.interval(Duration.ofSeconds(1));
Flux<String> fromIterable = Flux.fromIterable(list);
Flux<String> fromStream = Flux.fromStream(() -> stream);  // always use Supplier

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

---

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
| `collectList` | Flux to Mono\<List\> | `.collectList()` |
| `collectMap` | Flux to Mono\<Map\> | `.collectMap(Entity::getId)` |
| `delayElement` | Add delay per element | `.delayElement(Duration.ofMillis(100))` |

---

## flatMap vs concatMap vs flatMapSequential

```java
// flatMap -- CONCURRENT, unordered results
// Use when: order doesn't matter, max throughput
flux.flatMap(id -> fetchById(id), 16)  // concurrency = 16

// concatMap -- SEQUENTIAL, ordered, one at a time
// Use when: order matters, or downstream can't handle concurrent writes
flux.concatMap(id -> fetchById(id))

// flatMapSequential -- CONCURRENT execution, ORDERED results
// Use when: you want throughput AND ordering
flux.flatMapSequential(id -> fetchById(id), 8)
```

---

## Common Reactive Patterns

### Parallel Fetch (Zip)

```java
public Mono<DashboardDto> getDashboard(Long userId) {
    return Mono.zip(
        userService.findById(userId),
        orderService.findByUserId(userId).collectList(),
        walletService.getBalance(userId)
    ).map(tuple -> new DashboardDto(tuple.getT1(), tuple.getT2(), tuple.getT3()));
}
```

### switchIfEmpty + Defer (Cache-Miss Pattern)

```java
return cacheRepository.findByKey(key)
    .switchIfEmpty(Mono.defer(() -> dbRepository.findByKey(key)))
    .switchIfEmpty(Mono.error(new NotFoundException("Not found: " + key)));
```

> Always wrap `switchIfEmpty` fallback in `Mono.defer()` if the fallback is an eager publisher.

### Retry with Backoff

```java
.retryWhen(Retry.backoff(3, Duration.ofMillis(500))
    .maxBackoff(Duration.ofSeconds(5))
    .jitter(0.5)
    .filter(ex -> ex instanceof WebClientResponseException.ServiceUnavailable
               || ex instanceof ConnectException)
    .doBeforeRetry(signal -> log.warn("Retry #{}: {}",
        signal.totalRetries() + 1, signal.failure().getMessage()))
    .onRetryExhaustedThrow((spec, signal) ->
        new ServiceUnavailableException("Exhausted retries", signal.failure()))
)
```

### Wrap Blocking Code

```java
Mono.fromCallable(() -> legacyClient.blockingCall(id))
    .subscribeOn(Schedulers.boundedElastic())  // never block Netty thread
```

### Merge Patterns

```java
// merge -- concurrent, interleaved results
Flux<Notification> all = Flux.merge(emailNotifications, smsNotifications, pushNotifications);

// mergeSequential -- concurrent execution, ordered by source
Flux<Result> results = Flux.mergeSequential(source1, source2, source3);
```

---

## Error Handling

```java
// onErrorResume -- replace error with fallback publisher
.onErrorResume(R2dbcException.class, ex -> cacheService.getProduct(id))

// Selective by status code
.onErrorResume(WebClientResponseException.class, ex -> {
    if (ex.getStatusCode().is4xxClientError())
        return Mono.error(new BadRequestException(ex.getResponseBodyAsString()));
    return Mono.error(new ServiceUnavailableException("Downstream error"));
})

// onErrorMap -- transform error type
.onErrorMap(DataIntegrityViolationException.class,
    ex -> new DuplicateEmailException(dto.email(), ex))

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

## Backpressure Strategies

```java
// Buffer -- store excess (bounded)
flux.onBackpressureBuffer(1000, dropped -> log.warn("Dropped: {}", dropped),
    BufferOverflowStrategy.DROP_OLDEST);

// Drop -- discard when downstream slow
flux.onBackpressureDrop(dropped -> log.warn("Backpressure drop: {}", dropped));

// Latest -- keep only most recent
flux.onBackpressureLatest();

// limitRate -- request in batches (prefetch control)
flux.limitRate(100);           // request 100 at a time
flux.limitRate(100, 50);       // request 100, refill at 50 (low-tide)
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
// publishOn -- switch thread for DOWNSTREAM operators
flux
    .publishOn(Schedulers.parallel())
    .map(this::cpuIntensiveWork)
    .publishOn(Schedulers.boundedElastic())
    .flatMap(this::blockingIo)

// subscribeOn -- switch thread for ENTIRE chain (only first takes effect)
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

// WebFilter -- inject for all requests
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

> For Spring Boot 3.x, set `spring.reactor.context-propagation=auto` and add `io.micrometer:context-propagation` dependency for automatic MDC propagation.

---

## Annotated Controllers

```java
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {
    private final UserService userService;

    @GetMapping("/{id}")
    public Mono<ResponseEntity<UserResponse>> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @GetMapping
    public Flux<UserResponse> listUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return userService.findAll(PageRequest.of(page, size));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserResponse> createUser(@Valid @RequestBody CreateUserRequest request) {
        return userService.create(request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteUser(@PathVariable Long id) {
        return userService.delete(id);
    }

    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<UserEvent> streamUserEvents() {
        return userService.streamEvents();
    }
}
```

---

## Router Functions

```java
@Configuration
public class UserRouter {
    @Bean
    public RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .GET("/api/users/{id}", handler::getUser)
            .GET("/api/users", handler::listUsers)
            .POST("/api/users", handler::createUser)
            .PUT("/api/users/{id}", handler::updateUser)
            .DELETE("/api/users/{id}", handler::deleteUser)
            .build();
    }
}

@Component
@RequiredArgsConstructor
public class UserHandler {
    private final UserService userService;
    private final Validator validator;

    public Mono<ServerResponse> getUser(ServerRequest request) {
        Long id = Long.valueOf(request.pathVariable("id"));
        return userService.findById(id)
            .flatMap(user -> ServerResponse.ok().bodyValue(user))
            .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> createUser(ServerRequest request) {
        return request.bodyToMono(CreateUserRequest.class)
            .doOnNext(dto -> {
                var errors = new BeanPropertyBindingResult(dto, "dto");
                validator.validate(dto, errors);
                if (errors.hasErrors()) throw new ServerWebInputException(errors.toString());
            })
            .flatMap(userService::create)
            .flatMap(created -> ServerResponse.created(
                URI.create("/api/users/" + created.id()))
                .bodyValue(created));
    }
}
```

---

## R2DBC Repository

```java
public interface UserRepository extends ReactiveCrudRepository<UserEntity, Long> {
    Flux<UserEntity> findByStatus(UserStatus status);
    Mono<UserEntity> findByEmail(String email);
    Flux<UserEntity> findByCreatedAtAfter(Instant since);

    @Query("SELECT * FROM users WHERE status = :status ORDER BY created_at DESC LIMIT :limit")
    Flux<UserEntity> findActiveUsersLimited(String status, int limit);

    @Query("UPDATE users SET status = :status WHERE id = :id")
    @Modifying
    Mono<Integer> updateStatus(Long id, String status);

    Flux<UserEntity> findAllByStatus(UserStatus status, Pageable pageable);
    Mono<Long> countByStatus(UserStatus status);
}

@Table("users")
public class UserEntity {
    @Id
    private Long id;
    private String email;
    private String name;
    @Column("status")
    private String status;
    private Instant createdAt;
    private Instant updatedAt;
}
```

---

## R2DBC DatabaseClient

Use for complex joins, dynamic queries, or when repositories don't suffice.

```java
@Repository
@RequiredArgsConstructor
public class UserQueryRepository {
    private final DatabaseClient db;

    public Flux<UserWithOrdersDto> findUsersWithOrderCount(UserStatus status) {
        return db.sql("""
                SELECT u.id, u.email, u.name, COUNT(o.id) as order_count
                FROM users u
                LEFT JOIN orders o ON o.customer_id = u.id
                WHERE u.status = :status
                GROUP BY u.id, u.email, u.name
                ORDER BY order_count DESC
                """)
            .bind("status", status.name())
            .map(row -> new UserWithOrdersDto(
                row.get("id", Long.class),
                row.get("email", String.class),
                row.get("name", String.class),
                row.get("order_count", Long.class)
            ))
            .all();
    }

    // Dynamic query builder
    public Flux<UserEntity> search(String email, UserStatus status, int limit) {
        var query = new StringBuilder("SELECT * FROM users WHERE 1=1");
        var params = new HashMap<String, Object>();
        if (email != null) {
            query.append(" AND email LIKE :email");
            params.put("email", "%" + email + "%");
        }
        if (status != null) {
            query.append(" AND status = :status");
            params.put("status", status.name());
        }
        query.append(" LIMIT :limit");
        params.put("limit", limit);

        var spec = db.sql(query.toString());
        for (var entry : params.entrySet()) {
            spec = spec.bind(entry.getKey(), entry.getValue());
        }
        return spec.mapProperties(UserEntity.class).all();
    }
}
```

---

## Reactive Transactions

```java
@Service
@RequiredArgsConstructor
public class OrderService {
    private final OrderRepository orderRepository;
    private final InventoryRepository inventoryRepository;
    private final ReactiveTransactionManager transactionManager;

    // Declarative
    @Transactional
    public Mono<Order> createOrder(CreateOrderCommand cmd) {
        return orderRepository.save(toEntity(cmd))
            .flatMap(order -> inventoryRepository.decrementStock(
                cmd.productId(), cmd.quantity())
                .thenReturn(order));
    }

    // Programmatic (fine-grained control)
    public Mono<Order> transferStock(Long fromProductId, Long toProductId, int qty) {
        TransactionalOperator txOp = TransactionalOperator.create(transactionManager);
        return inventoryRepository.decrementStock(fromProductId, qty)
            .then(inventoryRepository.incrementStock(toProductId, qty))
            .then(orderRepository.logTransfer(fromProductId, toProductId, qty))
            .as(txOp::transactional);
    }
}
```

> Transaction rules: `@Transactional` on public methods only. Use `TransactionalOperator` for programmatic control. Never `block()` inside a transaction.

---

## WebClient Configuration

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient paymentWebClient() {
        ConnectionProvider provider = ConnectionProvider.builder("payment-pool")
            .maxConnections(200)
            .maxIdleTime(Duration.ofSeconds(30))
            .maxLifeTime(Duration.ofMinutes(5))
            .pendingAcquireTimeout(Duration.ofSeconds(10))
            .evictInBackground(Duration.ofSeconds(120))
            .build();

        HttpClient httpClient = HttpClient.create(provider)
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5_000)
            .responseTimeout(Duration.ofSeconds(10))
            .doOnConnected(conn -> conn
                .addHandlerLast(new ReadTimeoutHandler(10))
                .addHandlerLast(new WriteTimeoutHandler(10)));

        return WebClient.builder()
            .baseUrl("https://payment-service:8443")
            .clientConnector(new ReactorClientHttpConnector(httpClient))
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .defaultHeader(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)
            .codecs(c -> c.defaultCodecs().maxInMemorySize(2 * 1024 * 1024))
            .filter(logRequest())
            .filter(addAuthHeader())
            .build();
    }

    private ExchangeFilterFunction logRequest() {
        return ExchangeFilterFunction.ofRequestProcessor(req -> {
            log.debug(">>> {} {}", req.method(), req.url());
            return Mono.just(req);
        });
    }

    private ExchangeFilterFunction addAuthHeader() {
        return ExchangeFilterFunction.ofRequestProcessor(req ->
            Mono.deferContextual(ctx -> {
                String token = ctx.getOrDefault("authToken", "");
                return Mono.just(ClientRequest.from(req)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                    .build());
            }));
    }
}
```

---

## WebClient Usage

```java
@Service
@RequiredArgsConstructor
public class PaymentClient {
    private final WebClient paymentWebClient;

    // GET with error handling + retry
    public Mono<PaymentStatus> getPaymentStatus(String paymentId) {
        return paymentWebClient.get()
            .uri("/payments/{id}", paymentId)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError, response ->
                response.bodyToMono(ErrorResponse.class)
                    .flatMap(err -> Mono.error(new PaymentException(err.message()))))
            .onStatus(HttpStatusCode::is5xxServerError, response ->
                Mono.error(new ServiceUnavailableException("Payment service error")))
            .bodyToMono(PaymentStatus.class)
            .timeout(Duration.ofSeconds(5))
            .retryWhen(Retry.backoff(2, Duration.ofMillis(500))
                .filter(ex -> ex instanceof ServiceUnavailableException));
    }

    // POST with body
    public Mono<PaymentResult> processPayment(PaymentRequest request) {
        return paymentWebClient.post()
            .uri("/payments")
            .bodyValue(request)
            .retrieve()
            .bodyToMono(PaymentResult.class);
    }

    // Streaming response
    public Flux<PaymentEvent> streamPaymentEvents(String customerId) {
        return paymentWebClient.get()
            .uri("/payments/events/{customerId}", customerId)
            .accept(MediaType.TEXT_EVENT_STREAM)
            .retrieve()
            .bodyToFlux(PaymentEvent.class);
    }
}
```

---

## SSE with Sinks

```java
@Service
public class NotificationService {
    private final Sinks.Many<Notification> sink = Sinks.many().multicast()
        .onBackpressureBuffer(1000, false);

    public void publish(Notification notification) {
        sink.tryEmitNext(notification);
    }

    public Flux<Notification> subscribe() {
        return sink.asFlux()
            .onBackpressureDrop(n -> log.warn("Dropped notification: {}", n.id()));
    }

    // Per-user notifications
    private final Map<String, Sinks.Many<Notification>> userSinks = new ConcurrentHashMap<>();

    public Flux<Notification> subscribeUser(String userId) {
        return userSinks.computeIfAbsent(userId, id ->
            Sinks.many().multicast().onBackpressureBuffer(100, false))
            .asFlux()
            .doFinally(signal -> {
                if (signal == SignalType.CANCEL) userSinks.remove(userId);
            });
    }
}

// SSE controller with heartbeat
@RestController
@RequiredArgsConstructor
public class NotificationController {
    private final NotificationService notificationService;

    @GetMapping(value = "/api/notifications/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<Notification>> streamNotifications(
            @RequestHeader(value = "Last-Event-ID", required = false) String lastEventId) {
        return notificationService.subscribe()
            .map(n -> ServerSentEvent.<Notification>builder()
                .id(n.id())
                .event(n.type())
                .data(n)
                .build())
            .mergeWith(Flux.interval(Duration.ofSeconds(30))
                .map(tick -> ServerSentEvent.<Notification>builder()
                    .comment("heartbeat")
                    .build()));
    }
}
```

---

## Reactive Spring Security

```java
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http,
            ReactiveJwtDecoder jwtDecoder) {
        return http
            .csrf(ServerHttpSecurity.CsrfSpec::disable)
            .httpBasic(ServerHttpSecurity.HttpBasicSpec::disable)
            .formLogin(ServerHttpSecurity.FormLoginSpec::disable)
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtDecoder(jwtDecoder)))
            .authorizeExchange(exchange -> exchange
                .pathMatchers(HttpMethod.GET, "/api/public/**").permitAll()
                .pathMatchers("/actuator/health", "/actuator/info").permitAll()
                .pathMatchers("/api/admin/**").hasRole("ADMIN")
                .anyExchange().authenticated())
            .build();
    }
}

// JWT authentication filter (custom, when not using oauth2ResourceServer)
@Component
@RequiredArgsConstructor
public class JwtAuthenticationWebFilter implements WebFilter {
    private final JwtTokenValidator tokenValidator;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        return Mono.justOrEmpty(exchange.getRequest().getHeaders()
                .getFirst(HttpHeaders.AUTHORIZATION))
            .filter(header -> header.startsWith("Bearer "))
            .map(header -> header.substring(7))
            .flatMap(tokenValidator::validate)
            .flatMap(auth -> chain.filter(exchange)
                .contextWrite(ReactiveSecurityContextHolder.withAuthentication(auth)))
            .switchIfEmpty(chain.filter(exchange));
    }
}

// Method security
@PreAuthorize("hasRole('ADMIN')")
public Mono<List<UserResponse>> getAllUsers() { ... }

@PreAuthorize("hasRole('USER') and #userId == authentication.principal.subject")
public Mono<UserResponse> getUser(String userId) { ... }

// Custom permission evaluator
@PreAuthorize("@orderPermissionEvaluator.canAccess(authentication, #orderId)")
public Mono<Order> getOrder(Long orderId) { ... }
```

---

## StepVerifier Testing

```java
// Basic Mono
StepVerifier.create(userService.findById(1L))
    .expectNextMatches(user -> user.email().equals("alice@example.com"))
    .verifyComplete();

// Basic Flux
StepVerifier.create(userService.findAll())
    .expectNextCount(5)
    .verifyComplete();

// Error assertion
StepVerifier.create(userService.findById(999L))
    .expectError(NotFoundException.class)
    .verify();

// Error message
StepVerifier.create(userService.findById(999L))
    .expectErrorSatisfies(ex -> assertThat(ex)
        .isInstanceOf(NotFoundException.class)
        .hasMessage("User not found: 999"))
    .verify();

// Time-based with VirtualTimeScheduler
StepVerifier.withVirtualTime(() -> Flux.interval(Duration.ofSeconds(1)).take(3))
    .expectSubscription()
    .thenAwait(Duration.ofSeconds(3))
    .expectNextCount(3)
    .verifyComplete();

// With timeout (CI-safe)
StepVerifier.create(asyncOperation())
    .expectNextCount(1)
    .verifyComplete(Duration.ofSeconds(5));

// Context verification
StepVerifier.create(
    Mono.deferContextual(ctx -> Mono.just(ctx.get("traceId")))
        .contextWrite(Context.of("traceId", "abc-123"))
)
    .expectNext("abc-123")
    .verifyComplete();
```

---

## WebTestClient Testing

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

## PublisherProbe

Use to verify that a branch/fallback is actually subscribed to.

```java
@Test
void shouldSendNotificationOnConfirm() {
    var notificationProbe = PublisherProbe.empty();
    when(notificationPort.sendOrderConfirmation(any(), any()))
        .thenReturn(notificationProbe.mono());

    StepVerifier.create(orderService.createOrder(validCommand()))
        .expectNextMatches(r -> r.status() == OrderStatus.CONFIRMED)
        .verifyComplete();

    notificationProbe.assertWasSubscribed();
    notificationProbe.assertWasNotCancelled();
}

@Test
void shouldFallbackToDatabase() {
    var cacheProbe = PublisherProbe.empty();
    var dbProbe = PublisherProbe.of(Mono.just(cachedUser));

    when(cacheRepo.findByKey("config")).thenReturn(cacheProbe.mono());
    when(dbRepo.findByKey("config")).thenReturn(dbProbe.mono());

    StepVerifier.create(configService.getConfig("config"))
        .expectNextCount(1)
        .verifyComplete();

    cacheProbe.assertWasSubscribed();
    dbProbe.assertWasSubscribed();
}
```

---

## Testcontainers + R2DBC

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
            "r2dbc:postgresql://" + postgres.getHost() + ":"
            + postgres.getMappedPort(5432) + "/testdb");
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.flyway.url", postgres::getJdbcUrl);
    }

    @Autowired
    private UserRepository userRepository;

    @Test
    void shouldSaveAndFind() {
        var entity = new UserEntity(null, "alice@example.com", "Alice",
            "ACTIVE", Instant.now(), null);
        StepVerifier.create(userRepository.save(entity)
            .flatMap(saved -> userRepository.findById(saved.getId())))
            .expectNextMatches(u -> u.email().equals("alice@example.com"))
            .verifyComplete();
    }
}
```

---

## Performance Tuning

### R2DBC Pool + Netty (application.yml)

```yaml
spring:
  r2dbc:
    url: r2dbc:pool:postgresql://localhost:5432/mydb
    pool:
      initial-size: 10
      max-size: 50
      max-idle-time: 30m
      max-life-time: 60m
      max-acquire-time: 10s
      validation-query: SELECT 1
  reactor:
    context-propagation: auto

server:
  netty:
    connection-timeout: 10s
    max-keep-alive-requests: 10000
    idle-timeout: 60s
```

### JVM Flags (container)

```
-XX:+UseG1GC -XX:MaxGCPauseMillis=100
-XX:+UseStringDeduplication
-Dreactor.netty.ioWorkerCount=8
-Dreactor.schedulers.defaultPoolSize=8
```

### Profiling Checklist

- [ ] No `block()` on event loop threads
- [ ] Connection pool sized correctly (monitor via Micrometer)
- [ ] `flatMap` concurrency set (default 256 -- may be too high)
- [ ] `limitRate()` on high-throughput Flux
- [ ] `cache()` on expensive Mono subscribed multiple times

---

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `.block()` on event loop | Deadlock | `subscribeOn(boundedElastic())` |
| `Mono.just(expensiveCall())` | Eager execution | `Mono.fromCallable()` |
| `.switchIfEmpty(service.call())` | Eager fallback | `Mono.defer(() -> service.call())` |
| Returning `null` from `.map()` | NullPointerException | `flatMap()` + `Mono.empty()` |
| Ignoring publisher return | Nothing executes | Chain all publishers |
| `Thread.sleep()` in tests | Flaky, slow | `StepVerifier.withVirtualTime()` |
| Mutable shared state | Race conditions | Immutable objects, `Sinks` |
| `.toFuture().get()` | Blocks thread | Reactive pipeline end-to-end |
| No `maxInMemorySize` | `DataBufferLimitException` | Set in WebClient codecs |
