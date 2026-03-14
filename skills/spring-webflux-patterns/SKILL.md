---
name: spring-webflux-patterns
description: >
  Comprehensive Spring WebFlux patterns for reactive backend development.
  Covers Project Reactor fundamentals, reactive chain composition, error handling,
  R2DBC integration, WebClient, SSE, backpressure, schedulers, context propagation,
  reactive security, testing with StepVerifier/WebTestClient, performance tuning,
  and common anti-patterns. Use when building non-blocking reactive APIs with
  Spring Boot 3.x and Java 17+.
version: 1.0.0
---

# Spring WebFlux Patterns

Production-ready reactive patterns for Java 17+ / Spring Boot 3.x applications.

## Quick Reference

| Category | When to Use | Jump To |
|----------|------------|---------|
| Reactor Fundamentals | Understanding Mono/Flux/Operators | [Reactor Fundamentals](#reactor-fundamentals) |
| Chain Composition | Building reactive pipelines | [Chain Composition](#reactive-chain-composition) |
| Error Handling | Resilient reactive error strategies | [Error Handling](#error-handling-patterns) |
| Controllers | REST endpoints with WebFlux | [Controllers](#webflux-controllers) |
| R2DBC | Reactive database access | [R2DBC Integration](#r2dbc-integration) |
| WebClient | Reactive HTTP client | [WebClient](#webclient-patterns) |
| SSE | Server-Sent Events streaming | [SSE](#server-sent-events-sse) |
| Backpressure | Flow control strategies | [Backpressure](#backpressure-strategies) |
| Schedulers | Thread management | [Schedulers](#schedulers) |
| Context | MDC logging, context propagation | [Context](#context-propagation) |
| Security | Reactive Spring Security | [Security](#reactive-security) |
| Testing | StepVerifier, WebTestClient | [Testing](#testing) |
| Performance | R2DBC Pool, Netty tuning | [Performance](#performance-tuning) |
| Anti-Patterns | Common mistakes and fixes | [Anti-Patterns](#common-anti-patterns) |
| Migration | Spring MVC → WebFlux | [Migration](#migration-from-spring-mvc) |

---

## Dependencies

```xml
<!-- Spring WebFlux -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webflux</artifactId>
</dependency>

<!-- R2DBC with PostgreSQL -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-r2dbc</artifactId>
</dependency>
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>r2dbc-postgresql</artifactId>
    <scope>runtime</scope>
</dependency>

<!-- R2DBC Connection Pool -->
<dependency>
    <groupId>io.r2dbc</groupId>
    <artifactId>r2dbc-pool</artifactId>
</dependency>

<!-- Reactive Security -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>

<!-- Testing -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-test</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>io.projectreactor</groupId>
    <artifactId>reactor-test</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.springframework.security</groupId>
    <artifactId>spring-security-test</artifactId>
    <scope>test</scope>
</dependency>
```

---

## Reactor Fundamentals

### Mono — 0 or 1 Element

```java
// Creating Mono
Mono<String> empty = Mono.empty();
Mono<String> just = Mono.just("hello");
Mono<String> deferred = Mono.defer(() -> Mono.just(expensiveCall()));
Mono<String> fromCallable = Mono.fromCallable(() -> blockingCall());
Mono<String> fromSupplier = Mono.fromSupplier(() -> "computed");
Mono<Void> fromRunnable = Mono.fromRunnable(() -> sideEffect());

// Mono from CompletableFuture
Mono<String> fromFuture = Mono.fromFuture(() -> asyncService.call());

// Mono.error
Mono<String> error = Mono.error(new RuntimeException("failed"));
```

### Flux — 0 to N Elements

```java
// Creating Flux
Flux<String> just = Flux.just("a", "b", "c");
Flux<Integer> range = Flux.range(1, 10);
Flux<Long> interval = Flux.interval(Duration.ofSeconds(1));
Flux<String> fromIterable = Flux.fromIterable(list);
Flux<String> fromStream = Flux.fromStream(() -> stream); // lazy!
Flux<String> concat = Flux.concat(flux1, flux2);
Flux<String> merge = Flux.merge(flux1, flux2); // interleaved

// Generate (synchronous sink, 1 element per callback)
Flux<Integer> generated = Flux.generate(
    () -> 0, // initial state
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

### Key Operators — Quick Reference

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
| `zipWith` | Combine two publishers | `monoA.zipWith(monoB)` |
| `then` | Ignore elements, chain next | `.then(Mono.just("done"))` |
| `thenReturn` | Ignore elements, return value | `.thenReturn("done")` |
| `doOnNext` | Side-effect on element | `.doOnNext(e -> log.info(...))` |
| `doOnError` | Side-effect on error | `.doOnError(e -> log.error(...))` |
| `doFinally` | Cleanup (any termination) | `.doFinally(signal -> cleanup())` |
| `delayElement` | Add delay per element | `.delayElement(Duration.ofMillis(100))` |
| `cache` | Cache result | `.cache(Duration.ofMinutes(5))` |
| `share` | Share subscription (hot) | `.share()` |
| `collectList` | Flux → Mono<List> | `.collectList()` |
| `collectMap` | Flux → Mono<Map> | `.collectMap(Entity::getId)` |

---

## Reactive Chain Composition

### flatMap vs concatMap vs flatMapSequential

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

### switchIfEmpty — Guard Against Empty

```java
public Mono<User> findByIdOrThrow(Long id) {
    return userRepository.findById(id)
        .switchIfEmpty(Mono.error(
            new NotFoundException("User not found: " + id)
        ));
}

// Chain with fallback source
public Mono<Config> getConfig(String key) {
    return cacheRepository.findByKey(key)
        .switchIfEmpty(Mono.defer(() -> dbRepository.findByKey(key)))
        .switchIfEmpty(Mono.just(Config.defaultFor(key)));
}
```

> ⚠️ **Important**: Always wrap `switchIfEmpty` fallback in `Mono.defer()` if it's an eager publisher. Otherwise it executes regardless of emptiness.

### Zip — Parallel Fetch

```java
// Parallel independent calls
public Mono<DashboardDto> getDashboard(Long userId) {
    Mono<User> userMono = userService.findById(userId);
    Mono<List<Order>> ordersMono = orderService.findByUserId(userId).collectList();
    Mono<WalletBalance> balanceMono = walletService.getBalance(userId);

    return Mono.zip(userMono, ordersMono, balanceMono)
        .map(tuple -> new DashboardDto(
            tuple.getT1(),
            tuple.getT2(),
            tuple.getT3()
        ));
}

// Named combinator (cleaner than tuple)
public Mono<OrderSummary> buildSummary(Long orderId) {
    return Mono.zip(
        orderRepo.findById(orderId),
        paymentService.getPayment(orderId),
        shippingService.getTracking(orderId)
    ).map(tuple -> OrderSummary.builder()
        .order(tuple.getT1())
        .payment(tuple.getT2())
        .tracking(tuple.getT3())
        .build()
    );
}
```

### Merge — Interleaved Streams

```java
// Merge multiple sources (interleaved, all subscribed eagerly)
Flux<Notification> allNotifications = Flux.merge(
    emailNotifications,    // subscribed concurrently
    smsNotifications,
    pushNotifications
);

// mergeWith — instance method
Flux<Event> allEvents = internalEvents.mergeWith(externalEvents);

// mergeSequential — concurrent execution, ordered by source
Flux<Result> results = Flux.mergeSequential(source1, source2, source3);
```

### Transform and TransformDeferred

```java
// transform — applied once at assembly time
public <T> Function<Flux<T>, Flux<T>> withLogging(String label) {
    return flux -> flux
        .doOnNext(e -> log.debug("[{}] element: {}", label, e))
        .doOnError(e -> log.error("[{}] error: {}", label, e.getMessage()))
        .doOnComplete(() -> log.debug("[{}] complete", label));
}

flux.transform(withLogging("orders"));

// transformDeferred — applied per subscriber (lazy)
flux.transformDeferred(f -> f.retryWhen(Retry.backoff(3, Duration.ofSeconds(1))));
```

---

## Error Handling Patterns

### onErrorResume — Replace Error with Fallback

```java
// Fallback to cache on DB error
public Mono<Product> getProduct(String id) {
    return productRepository.findById(id)
        .onErrorResume(R2dbcException.class, ex -> {
            log.warn("DB error, falling back to cache: {}", ex.getMessage());
            return cacheService.getProduct(id);
        });
}

// Selective error handling
public Mono<Response> callExternal(Request req) {
    return webClient.post()
        .bodyValue(req)
        .retrieve()
        .bodyToMono(Response.class)
        .onErrorResume(WebClientResponseException.class, ex -> {
            if (ex.getStatusCode().is4xxClientError()) {
                return Mono.error(new BadRequestException(ex.getResponseBodyAsString()));
            }
            return Mono.error(new ServiceUnavailableException("Downstream error"));
        });
}
```

### onErrorMap — Transform Error Type

```java
public Mono<User> createUser(UserDto dto) {
    return userRepository.save(toEntity(dto))
        .onErrorMap(DataIntegrityViolationException.class,
            ex -> new DuplicateEmailException(dto.email(), ex));
}
```

### onErrorReturn — Default Value on Error

```java
// Simple default (use sparingly — hides errors)
public Mono<Integer> getInventoryCount(String sku) {
    return inventoryService.getCount(sku)
        .onErrorReturn(0);
}
```

### Retry with Backoff

```java
// Retry with exponential backoff
public Mono<Response> callWithRetry(Request request) {
    return webClient.post()
        .bodyValue(request)
        .retrieve()
        .bodyToMono(Response.class)
        .retryWhen(Retry.backoff(3, Duration.ofMillis(500))
            .maxBackoff(Duration.ofSeconds(5))
            .jitter(0.5)
            .filter(ex -> ex instanceof WebClientResponseException.ServiceUnavailable
                       || ex instanceof ConnectException)
            .doBeforeRetry(signal -> log.warn(
                "Retry #{} due to: {}",
                signal.totalRetries() + 1,
                signal.failure().getMessage()
            ))
            .onRetryExhaustedThrow((spec, signal) ->
                new ServiceUnavailableException(
                    "Exhausted retries after " + signal.totalRetries(),
                    signal.failure()
                )
            )
        );
}
```

### timeout

```java
public Mono<Result> withTimeout(Mono<Result> source) {
    return source
        .timeout(Duration.ofSeconds(5))
        .onErrorMap(TimeoutException.class,
            ex -> new GatewayTimeoutException("Operation timed out"));
}
```

### Global Error Handler

```java
@Component
@Order(-2)
public class GlobalErrorWebExceptionHandler extends AbstractErrorWebExceptionHandler {

    public GlobalErrorWebExceptionHandler(
            ErrorAttributes errorAttributes,
            WebProperties.Resources resources,
            ApplicationContext applicationContext,
            ServerCodecConfigurer configurer) {
        super(errorAttributes, resources, applicationContext);
        setMessageWriters(configurer.getWriters());
    }

    @Override
    protected RouterFunction<ServerResponse> getRoutingFunction(ErrorAttributes attrs) {
        return RouterFunctions.route(RequestPredicates.all(), this::renderError);
    }

    private Mono<ServerResponse> renderError(ServerRequest request) {
        var error = getError(request);
        var status = determineStatus(error);
        var body = ProblemDetail.forStatusAndDetail(status, error.getMessage());

        return ServerResponse.status(status)
            .contentType(MediaType.APPLICATION_PROBLEM_JSON)
            .bodyValue(body);
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

## WebFlux Controllers

### Annotated Controller Style

```java
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @GetMapping
    public Flux<UserDto> findAll(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return userService.findAll(page, size);
    }

    @GetMapping("/{id}")
    public Mono<ResponseEntity<UserDto>> findById(@PathVariable Long id) {
        return userService.findById(id)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserDto> create(@Valid @RequestBody Mono<CreateUserRequest> request) {
        return request.flatMap(userService::create);
    }

    @PutMapping("/{id}")
    public Mono<ResponseEntity<UserDto>> update(
            @PathVariable Long id,
            @Valid @RequestBody Mono<UpdateUserRequest> request) {
        return request
            .flatMap(req -> userService.update(id, req))
            .map(ResponseEntity::ok);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> delete(@PathVariable Long id) {
        return userService.delete(id);
    }

    // Streaming response
    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<UserDto> streamUsers() {
        return userService.streamAll();
    }
}
```

### Router Function Style

```java
@Configuration
public class UserRouter {

    @Bean
    public RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .path("/api/v1/users", builder -> builder
                .GET("", handler::findAll)
                .GET("/{id}", handler::findById)
                .POST("", contentType(APPLICATION_JSON), handler::create)
                .PUT("/{id}", contentType(APPLICATION_JSON), handler::update)
                .DELETE("/{id}", handler::delete)
            )
            .build();
    }
}

@Component
@RequiredArgsConstructor
public class UserHandler {

    private final UserService userService;
    private final Validator validator;

    public Mono<ServerResponse> findAll(ServerRequest request) {
        int page = request.queryParam("page").map(Integer::parseInt).orElse(0);
        int size = request.queryParam("size").map(Integer::parseInt).orElse(20);

        return ServerResponse.ok()
            .contentType(APPLICATION_JSON)
            .body(userService.findAll(page, size), UserDto.class);
    }

    public Mono<ServerResponse> findById(ServerRequest request) {
        Long id = Long.parseLong(request.pathVariable("id"));
        return userService.findById(id)
            .flatMap(user -> ServerResponse.ok()
                .contentType(APPLICATION_JSON)
                .bodyValue(user))
            .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> create(ServerRequest request) {
        return request.bodyToMono(CreateUserRequest.class)
            .doOnNext(this::validate)
            .flatMap(userService::create)
            .flatMap(user -> ServerResponse
                .created(URI.create("/api/v1/users/" + user.id()))
                .contentType(APPLICATION_JSON)
                .bodyValue(user));
    }

    public Mono<ServerResponse> update(ServerRequest request) {
        Long id = Long.parseLong(request.pathVariable("id"));
        return request.bodyToMono(UpdateUserRequest.class)
            .doOnNext(this::validate)
            .flatMap(req -> userService.update(id, req))
            .flatMap(user -> ServerResponse.ok()
                .contentType(APPLICATION_JSON)
                .bodyValue(user));
    }

    public Mono<ServerResponse> delete(ServerRequest request) {
        Long id = Long.parseLong(request.pathVariable("id"));
        return userService.delete(id)
            .then(ServerResponse.noContent().build());
    }

    private void validate(Object target) {
        var errors = new BeanPropertyBindingResult(target, target.getClass().getSimpleName());
        validator.validate(target, errors);
        if (errors.hasErrors()) {
            throw new ServerWebInputException("Validation failed", null, errors);
        }
    }
}
```

---

## R2DBC Integration

### Repository Pattern

```java
// Entity
@Table("users")
public record UserEntity(
    @Id Long id,
    String email,
    String name,
    boolean active,
    Instant createdAt,
    Instant updatedAt
) {}

// Repository
public interface UserRepository extends ReactiveCrudRepository<UserEntity, Long> {

    Mono<UserEntity> findByEmail(String email);

    @Query("SELECT * FROM users WHERE active = true ORDER BY created_at DESC LIMIT :limit OFFSET :offset")
    Flux<UserEntity> findActiveUsers(int limit, long offset);

    @Query("SELECT COUNT(*) FROM users WHERE active = true")
    Mono<Long> countActive();

    Mono<Boolean> existsByEmail(String email);

    @Modifying
    @Query("UPDATE users SET active = false, updated_at = NOW() WHERE id = :id")
    Mono<Integer> deactivate(Long id);
}
```

### DatabaseClient for Complex Queries

```java
@Repository
@RequiredArgsConstructor
public class UserCustomRepository {

    private final DatabaseClient databaseClient;

    public Flux<UserEntity> search(UserSearchCriteria criteria) {
        var sql = new StringBuilder("SELECT * FROM users WHERE 1=1");
        var bindings = new HashMap<String, Object>();

        if (criteria.name() != null) {
            sql.append(" AND name ILIKE :name");
            bindings.put("name", "%" + criteria.name() + "%");
        }
        if (criteria.email() != null) {
            sql.append(" AND email = :email");
            bindings.put("email", criteria.email());
        }
        if (criteria.active() != null) {
            sql.append(" AND active = :active");
            bindings.put("active", criteria.active());
        }

        sql.append(" ORDER BY created_at DESC LIMIT :limit OFFSET :offset");
        bindings.put("limit", criteria.size());
        bindings.put("offset", (long) criteria.page() * criteria.size());

        var spec = databaseClient.sql(sql.toString());
        for (var entry : bindings.entrySet()) {
            spec = spec.bind(entry.getKey(), entry.getValue());
        }

        return spec.map((row, metadata) -> new UserEntity(
                row.get("id", Long.class),
                row.get("email", String.class),
                row.get("name", String.class),
                Boolean.TRUE.equals(row.get("active", Boolean.class)),
                row.get("created_at", Instant.class),
                row.get("updated_at", Instant.class)
            ))
            .all();
    }
}
```

### Reactive Transactions

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final InventoryRepository inventoryRepository;
    private final PaymentRepository paymentRepository;

    // Declarative transaction
    @Transactional
    public Mono<OrderDto> createOrder(CreateOrderRequest request) {
        return inventoryRepository.decrementStock(request.productId(), request.quantity())
            .filter(updated -> updated > 0)
            .switchIfEmpty(Mono.error(new InsufficientStockException()))
            .then(orderRepository.save(toEntity(request)))
            .flatMap(order -> paymentRepository.save(createPayment(order))
                .thenReturn(order))
            .map(this::toDto);
    }

    // Programmatic transaction with TransactionalOperator
    private final TransactionalOperator txOperator;

    public Mono<OrderDto> createOrderProgrammatic(CreateOrderRequest request) {
        return inventoryRepository.decrementStock(request.productId(), request.quantity())
            .filter(updated -> updated > 0)
            .switchIfEmpty(Mono.error(new InsufficientStockException()))
            .then(orderRepository.save(toEntity(request)))
            .flatMap(order -> paymentRepository.save(createPayment(order))
                .thenReturn(order))
            .map(this::toDto)
            .as(txOperator::transactional); // wraps in transaction
    }
}
```

### R2DBC Configuration

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://localhost:5432/mydb
    username: ${DB_USER}
    password: ${DB_PASS}
    pool:
      initial-size: 5
      max-size: 20
      max-idle-time: 30m
      max-life-time: 60m
      validation-query: SELECT 1
```

```java
@Configuration
public class R2dbcConfig extends AbstractR2dbcConfiguration {

    @Override
    @Bean
    public ConnectionFactory connectionFactory() {
        return ConnectionFactoryBuilder
            .withUrl("r2dbc:postgresql://localhost:5432/mydb")
            .username("user")
            .password("pass")
            .build();
    }

    // Custom converters
    @Override
    protected List<Object> getCustomConverters() {
        return List.of(
            new InstantToLocalDateTimeConverter(),
            new JsonToMapConverter()
        );
    }
}
```

---

## WebClient Patterns

### Configuration

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient paymentWebClient() {
        return WebClient.builder()
            .baseUrl("https://api.payment.example.com")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .defaultHeader(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)
            .filter(logRequest())
            .filter(logResponse())
            .codecs(configurer -> configurer
                .defaultCodecs()
                .maxInMemorySize(2 * 1024 * 1024)) // 2MB
            .build();
    }

    @Bean
    public WebClient resilientWebClient() {
        var httpClient = HttpClient.create()
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5000)
            .responseTimeout(Duration.ofSeconds(10))
            .doOnConnected(conn -> conn
                .addHandlerLast(new ReadTimeoutHandler(10))
                .addHandlerLast(new WriteTimeoutHandler(10)));

        return WebClient.builder()
            .clientConnector(new ReactorClientHttpConnector(httpClient))
            .build();
    }

    // Connection pooling
    @Bean
    public WebClient pooledWebClient() {
        var provider = ConnectionProvider.builder("custom")
            .maxConnections(100)
            .maxIdleTime(Duration.ofSeconds(30))
            .maxLifeTime(Duration.ofMinutes(5))
            .pendingAcquireTimeout(Duration.ofSeconds(5))
            .evictInBackground(Duration.ofSeconds(30))
            .metrics(true)
            .build();

        var httpClient = HttpClient.create(provider);

        return WebClient.builder()
            .clientConnector(new ReactorClientHttpConnector(httpClient))
            .build();
    }

    private ExchangeFilterFunction logRequest() {
        return ExchangeFilterFunction.ofRequestProcessor(request -> {
            log.debug("Request: {} {}", request.method(), request.url());
            return Mono.just(request);
        });
    }

    private ExchangeFilterFunction logResponse() {
        return ExchangeFilterFunction.ofResponseProcessor(response -> {
            log.debug("Response: {}", response.statusCode());
            return Mono.just(response);
        });
    }
}
```

### Usage Patterns

```java
@Service
@RequiredArgsConstructor
public class PaymentClient {

    private final WebClient paymentWebClient;

    // GET with error handling
    public Mono<PaymentDto> getPayment(String paymentId) {
        return paymentWebClient.get()
            .uri("/payments/{id}", paymentId)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError, response ->
                response.bodyToMono(ErrorResponse.class)
                    .flatMap(body -> Mono.error(
                        new PaymentNotFoundException(body.message())
                    ))
            )
            .onStatus(HttpStatusCode::is5xxServerError, response ->
                Mono.error(new PaymentServiceException("Payment service error"))
            )
            .bodyToMono(PaymentDto.class)
            .timeout(Duration.ofSeconds(5))
            .retryWhen(Retry.backoff(3, Duration.ofMillis(500))
                .filter(ex -> ex instanceof PaymentServiceException));
    }

    // POST with body
    public Mono<PaymentDto> createPayment(CreatePaymentRequest request) {
        return paymentWebClient.post()
            .uri("/payments")
            .bodyValue(request)
            .retrieve()
            .bodyToMono(PaymentDto.class);
    }

    // Exchange for full response access
    public Mono<PaymentDto> getPaymentWithHeaders(String paymentId) {
        return paymentWebClient.get()
            .uri("/payments/{id}", paymentId)
            .exchangeToMono(response -> {
                String requestId = response.headers()
                    .asHttpHeaders()
                    .getFirst("X-Request-Id");
                log.info("Request-Id: {}", requestId);

                if (response.statusCode().is2xxSuccessful()) {
                    return response.bodyToMono(PaymentDto.class);
                }
                return response.createError();
            });
    }

    // Streaming response
    public Flux<PaymentEvent> streamPaymentEvents(String accountId) {
        return paymentWebClient.get()
            .uri("/accounts/{id}/events", accountId)
            .accept(MediaType.TEXT_EVENT_STREAM)
            .retrieve()
            .bodyToFlux(PaymentEvent.class);
    }
}
```

---

## Server-Sent Events (SSE)

### SSE Endpoint

```java
@RestController
@RequestMapping("/api/v1/notifications")
@RequiredArgsConstructor
public class NotificationController {

    private final NotificationService notificationService;

    // Simple SSE stream
    @GetMapping(produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<NotificationDto>> streamNotifications(
            @RequestParam Long userId) {
        return notificationService.getNotificationStream(userId)
            .map(notification -> ServerSentEvent.<NotificationDto>builder()
                .id(notification.id().toString())
                .event(notification.type())
                .data(notification)
                .retry(Duration.ofSeconds(5))
                .build());
    }

    // SSE with heartbeat to keep connection alive
    @GetMapping(value = "/live", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<NotificationDto>> liveStream(
            @RequestParam Long userId) {
        Flux<ServerSentEvent<NotificationDto>> heartbeat = Flux.interval(Duration.ofSeconds(30))
            .map(i -> ServerSentEvent.<NotificationDto>builder()
                .event("heartbeat")
                .comment("keep-alive")
                .build());

        Flux<ServerSentEvent<NotificationDto>> notifications =
            notificationService.getNotificationStream(userId)
                .map(n -> ServerSentEvent.<NotificationDto>builder()
                    .id(n.id().toString())
                    .event(n.type())
                    .data(n)
                    .build());

        return Flux.merge(heartbeat, notifications);
    }
}
```

### SSE with Sinks (Push-based)

```java
@Service
public class NotificationService {

    // Many subscribers, replay last element
    private final Sinks.Many<NotificationDto> sink =
        Sinks.many().multicast().onBackpressureBuffer();

    public void pushNotification(NotificationDto notification) {
        sink.tryEmitNext(notification);
    }

    public Flux<NotificationDto> getNotificationStream(Long userId) {
        return sink.asFlux()
            .filter(n -> n.userId().equals(userId));
    }
}
```

---

## Backpressure Strategies

```java
// Buffer — store excess elements (risk OOM if unbounded)
flux.onBackpressureBuffer(1000) // bounded buffer
    .subscribe(this::process);

// Buffer with overflow strategy
flux.onBackpressureBuffer(
    1000,
    dropped -> log.warn("Dropped: {}", dropped),
    BufferOverflowStrategy.DROP_OLDEST
);

// Drop — discard elements when downstream is slow
flux.onBackpressureDrop(dropped ->
    log.warn("Backpressure drop: {}", dropped)
);

// Latest — keep only the most recent
flux.onBackpressureLatest();

// limitRate — request elements in batches (prefetch control)
flux.limitRate(100)         // request 100 at a time
    .flatMap(this::process);

flux.limitRate(100, 50);    // request 100, then refill at 50 (low-tide)

// limitRequest — cap total elements
flux.limitRequest(1000);    // complete after 1000 elements
```

---

## Schedulers

### publishOn vs subscribeOn

```java
// publishOn — switch thread for DOWNSTREAM operators
flux
    .filter(this::heavyFilter)      // runs on current thread
    .publishOn(Schedulers.parallel()) // switch ↓
    .map(this::cpuIntensiveWork)     // runs on parallel scheduler
    .publishOn(Schedulers.boundedElastic()) // switch ↓
    .flatMap(this::blockingIo)       // runs on boundedElastic

// subscribeOn — switch thread for ENTIRE chain (upstream + downstream)
// Only the FIRST subscribeOn takes effect
Mono.fromCallable(() -> blockingDbCall())
    .subscribeOn(Schedulers.boundedElastic()) // entire chain on boundedElastic
    .map(this::transform);
```

### Scheduler Types

| Scheduler | Use Case | Thread Pool |
|-----------|----------|-------------|
| `Schedulers.parallel()` | CPU-bound work | Fixed, CPU cores |
| `Schedulers.boundedElastic()` | Blocking I/O wrapping | Bounded, grows as needed |
| `Schedulers.single()` | Sequential, single-threaded | Single thread |
| `Schedulers.immediate()` | Current thread (no switch) | N/A |
| `Schedulers.fromExecutor(exec)` | Custom executor | User-defined |

### Wrapping Blocking Code

```java
// CORRECT — wrap blocking call in boundedElastic
public Mono<LegacyResult> callLegacyService(String id) {
    return Mono.fromCallable(() -> legacyClient.blockingCall(id))
        .subscribeOn(Schedulers.boundedElastic());
}

// WRONG — blocking on event loop
public Mono<LegacyResult> callLegacyServiceBad(String id) {
    return Mono.just(legacyClient.blockingCall(id)); // ❌ blocks Netty thread
}
```

---

## Context Propagation

### Reactor Context

```java
// Writing to context
public Mono<ServerResponse> handleRequest(ServerRequest request) {
    String traceId = request.headers().firstHeader("X-Trace-Id");
    return handler.process(request)
        .contextWrite(Context.of("traceId", traceId));
}

// Reading from context
public Mono<String> processWithTracing() {
    return Mono.deferContextual(ctx -> {
        String traceId = ctx.getOrDefault("traceId", "unknown");
        log.info("Processing with traceId: {}", traceId);
        return doWork();
    });
}

// Context in WebFilter (inject for all requests)
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

### MDC Logging in Reactive

```java
// Automatic context propagation (Reactor 3.5+ / Micrometer Context Propagation)
// application.properties:
// spring.reactor.context-propagation=auto

// Or manual MDC hooks
@Configuration
public class MdcContextConfig {

    @PostConstruct
    public void configureMdcHook() {
        Hooks.onEachOperator("mdc",
            Operators.lift((scannable, subscriber) ->
                new MdcContextSubscriber<>(subscriber)));
    }
}

// Using context-propagation library (recommended for Spring Boot 3.x)
// Add dependency: io.micrometer:context-propagation
// MDC values automatically propagate through reactive chain
```

---

## Reactive Security

### SecurityWebFilterChain Configuration

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(ServerHttpSecurity.CsrfSpec::disable)
            .authorizeExchange(exchanges -> exchanges
                .pathMatchers("/api/v1/auth/**").permitAll()
                .pathMatchers("/api/v1/public/**").permitAll()
                .pathMatchers("/actuator/health").permitAll()
                .pathMatchers(HttpMethod.GET, "/api/v1/products/**").permitAll()
                .pathMatchers("/api/v1/admin/**").hasRole("ADMIN")
                .anyExchange().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtDecoder(jwtDecoder()))
            )
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint((exchange, denied) ->
                    Mono.fromRunnable(() ->
                        exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED)))
                .accessDeniedHandler((exchange, denied) ->
                    Mono.fromRunnable(() ->
                        exchange.getResponse().setStatusCode(HttpStatus.FORBIDDEN)))
            )
            .build();
    }

    @Bean
    public ReactiveJwtDecoder jwtDecoder() {
        return ReactiveJwtDecoders.fromIssuerLocation("https://auth.example.com");
    }

    @Bean
    public ReactiveUserDetailsService userDetailsService() {
        return username -> userRepository.findByUsername(username)
            .map(user -> User.withUsername(user.username())
                .password(user.password())
                .roles(user.roles().toArray(String[]::new))
                .build())
            .switchIfEmpty(Mono.error(
                new UsernameNotFoundException("User not found: " + username)));
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
```

### Accessing Security Context

```java
@RestController
@RequestMapping("/api/v1/profile")
public class ProfileController {

    @GetMapping
    public Mono<UserProfile> getProfile() {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(auth -> (Jwt) auth.getPrincipal())
            .flatMap(jwt -> userService.findBySubject(jwt.getSubject()));
    }

    // Method-level security
    @PreAuthorize("hasRole('ADMIN')")
    @DeleteMapping("/{id}")
    public Mono<Void> deleteUser(@PathVariable Long id) {
        return userService.delete(id);
    }
}
```

---

## Testing

### StepVerifier

```java
@Test
void shouldFindUserById() {
    Mono<UserDto> result = userService.findById(1L);

    StepVerifier.create(result)
        .assertNext(user -> {
            assertThat(user.id()).isEqualTo(1L);
            assertThat(user.email()).isEqualTo("test@example.com");
        })
        .verifyComplete();
}

@Test
void shouldStreamActiveUsers() {
    Flux<UserDto> result = userService.findActive();

    StepVerifier.create(result)
        .expectNextCount(3)
        .verifyComplete();
}

@Test
void shouldReturnErrorWhenNotFound() {
    Mono<UserDto> result = userService.findById(999L);

    StepVerifier.create(result)
        .verifyError(NotFoundException.class);
}

@Test
void shouldRetryOnTransientError() {
    // Use virtual time for testing delays
    StepVerifier.withVirtualTime(() -> serviceWithRetry.call())
        .expectSubscription()
        .thenAwait(Duration.ofSeconds(10))
        .expectNext("success")
        .verifyComplete();
}
```

### WebTestClient

```java
@SpringBootTest
@AutoConfigureWebTestClient
class UserControllerTest {

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void shouldGetUser() {
        webTestClient.get()
            .uri("/api/v1/users/{id}", 1)
            .exchange()
            .expectStatus().isOk()
            .expectBody(UserDto.class)
            .value(user -> {
                assertThat(user.id()).isEqualTo(1L);
                assertThat(user.email()).isNotBlank();
            });
    }

    @Test
    void shouldCreateUser() {
        var request = new CreateUserRequest("test@example.com", "Test User");

        webTestClient.post()
            .uri("/api/v1/users")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody(UserDto.class)
            .value(user -> {
                assertThat(user.id()).isNotNull();
                assertThat(user.email()).isEqualTo("test@example.com");
            });
    }

    @Test
    void shouldReturn404WhenNotFound() {
        webTestClient.get()
            .uri("/api/v1/users/{id}", 999)
            .exchange()
            .expectStatus().isNotFound();
    }

    @Test
    void shouldStreamSSE() {
        webTestClient.get()
            .uri("/api/v1/notifications?userId=1")
            .accept(MediaType.TEXT_EVENT_STREAM)
            .exchange()
            .expectStatus().isOk()
            .returnResult(NotificationDto.class)
            .getResponseBody()
            .as(StepVerifier::create)
            .expectNextCount(5)
            .thenCancel()
            .verify();
    }

    // Authenticated requests
    @Test
    @WithMockUser(roles = "ADMIN")
    void shouldAllowAdminAccess() {
        webTestClient.get()
            .uri("/api/v1/admin/users")
            .exchange()
            .expectStatus().isOk();
    }
}
```

### PublisherProbe — Verify Reactive Paths

```java
@Test
void shouldUseCacheFallbackOnDbError() {
    PublisherProbe<Product> cacheProbe = PublisherProbe.of(
        Mono.just(new Product("cached"))
    );

    when(dbRepository.findById(anyString()))
        .thenReturn(Mono.error(new R2dbcException("DB down")));
    when(cacheService.getProduct(anyString()))
        .thenReturn(cacheProbe.mono());

    StepVerifier.create(productService.getProduct("123"))
        .expectNextMatches(p -> p.name().equals("cached"))
        .verifyComplete();

    cacheProbe.assertWasSubscribed();
    cacheProbe.assertWasRequested();
}
```

---

## Performance Tuning

### R2DBC Connection Pool

```yaml
spring:
  r2dbc:
    url: r2dbc:pool:postgresql://localhost:5432/mydb
    pool:
      initial-size: 10
      max-size: 50          # ~ 2x CPU cores for typical load
      max-idle-time: 30m
      max-life-time: 60m
      max-create-connection-time: 5s
      max-acquire-time: 10s
      validation-query: SELECT 1
      validation-depth: REMOTE  # validates with actual DB query
```

### Netty Tuning

```java
@Configuration
public class NettyConfig {

    @Bean
    public WebServerFactoryCustomizer<NettyReactiveWebServerFactory> nettyCustomizer() {
        return factory -> factory.addServerCustomizers(httpServer -> httpServer
            .option(ChannelOption.SO_BACKLOG, 128)
            .childOption(ChannelOption.SO_KEEPALIVE, true)
            .childOption(ChannelOption.TCP_NODELAY, true)
            .accessLog(true)
            .metrics(true, uri -> {
                // Normalize URI for metrics (avoid high cardinality)
                if (uri.startsWith("/api/v1/users/")) return "/api/v1/users/{id}";
                return uri;
            })
        );
    }
}
```

```yaml
# application.yml — Netty settings
server:
  netty:
    connection-timeout: 5s
    idle-timeout: 60s
    max-keep-alive-requests: 1000
    h2c-max-content-length: 0   # disable HTTP/2 cleartext
  http2:
    enabled: true                # enable HTTP/2 over TLS
```

### Memory and Buffer Tuning

```yaml
spring:
  codec:
    max-in-memory-size: 2MB     # max buffer for request/response body

# For large file uploads, use streaming instead of buffering
```

---

## Common Anti-Patterns

### ❌ Calling .block() Inside Reactive Chain

```java
// WRONG — blocks Netty event loop, causes thread starvation
public Mono<OrderDto> getOrder(Long id) {
    User user = userService.findById(id).block(); // ❌ NEVER do this
    return orderService.findByUser(user);
}

// CORRECT — compose reactively
public Mono<OrderDto> getOrder(Long id) {
    return userService.findById(id)
        .flatMap(orderService::findByUser);
}
```

### ❌ subscribe() Inside Chain

```java
// WRONG — fire-and-forget, loses error handling and backpressure
public Mono<Void> processOrder(Order order) {
    auditService.log(order).subscribe(); // ❌ detached subscription
    return orderRepo.save(order).then();
}

// CORRECT — compose in chain
public Mono<Void> processOrder(Order order) {
    return orderRepo.save(order)
        .then(auditService.log(order));
}

// Or if truly fire-and-forget is needed:
public Mono<Void> processOrder(Order order) {
    return orderRepo.save(order)
        .doOnSuccess(saved -> auditService.log(order)
            .subscribe(null, ex -> log.error("Audit failed", ex)));
        // ↑ Only acceptable in doOnSuccess/doOnNext, not in the main chain
}
```

### ❌ Thread.sleep() in Reactive Code

```java
// WRONG — blocks Netty thread
public Mono<String> withDelay() {
    Thread.sleep(1000); // ❌
    return Mono.just("result");
}

// CORRECT — non-blocking delay
public Mono<String> withDelay() {
    return Mono.just("result")
        .delayElement(Duration.ofSeconds(1));
}
```

### ❌ Shared Mutable State

```java
// WRONG — race conditions
private int counter = 0; // ❌ shared mutable state

public Mono<Void> process(Event event) {
    counter++; // ❌ not thread-safe
    return Mono.empty();
}

// CORRECT — use AtomicInteger or Reactor constructs
private final AtomicInteger counter = new AtomicInteger(0);

public Mono<Void> process(Event event) {
    counter.incrementAndGet();
    return Mono.empty();
}
```

### ❌ Ignoring Return Values

```java
// WRONG — nothing happens (cold publisher, nobody subscribes)
public void deleteUser(Long id) {
    userRepository.deleteById(id); // ❌ returns Mono<Void>, never subscribed
}

// CORRECT — return the Mono
public Mono<Void> deleteUser(Long id) {
    return userRepository.deleteById(id);
}
```

### ❌ Using Mono.just() for Lazy Evaluation

```java
// WRONG — expensiveCall() executes immediately regardless
public Mono<String> lazy() {
    return Mono.just(expensiveCall()); // ❌ eager
}

// CORRECT — defer or fromCallable for lazy evaluation
public Mono<String> lazy() {
    return Mono.defer(() -> Mono.just(expensiveCall()));
    // or
    return Mono.fromCallable(() -> expensiveCall());
}
```

---

## Migration from Spring MVC

### When to Migrate

| Factor | Stay with MVC | Move to WebFlux |
|--------|---------------|-----------------|
| Team experience | Team knows MVC well | Team comfortable with reactive |
| Dependencies | Blocking JDBC, JPA | R2DBC, reactive drivers available |
| Use case | CRUD, few concurrent requests | Streaming, high concurrency, SSE |
| Existing codebase | Large MVC codebase | New service or isolated module |
| Debugging | Easier stack traces | Harder to debug async flows |

### Migration Steps

1. **Start with new services** — don't rewrite existing MVC services
2. **Replace RestTemplate → WebClient** (WebClient works in both MVC and WebFlux)
3. **Replace JDBC/JPA → R2DBC** for database access
4. **Replace @Controller → @RestController with Mono/Flux** return types
5. **Replace Spring Security → Reactive Security** (SecurityWebFilterChain)
6. **Replace thread-local patterns** → Reactor Context
7. **Replace @Async** → reactive chain composition

### Coexistence

```java
// WebClient can be used in Spring MVC projects
// This is a good first step before full migration
@Service
public class MvcServiceUsingWebClient {

    private final WebClient webClient;

    // In MVC, you CAN use .block() at the controller level
    public ResponseEntity<UserDto> getUser(Long id) {
        UserDto user = webClient.get()
            .uri("/users/{id}", id)
            .retrieve()
            .bodyToMono(UserDto.class)
            .block(); // OK in MVC, but NOT in WebFlux
        return ResponseEntity.ok(user);
    }
}
```

---

## Checklist

- [ ] No `.block()` calls in WebFlux code paths
- [ ] No `Thread.sleep()` or blocking I/O on event loop threads
- [ ] All blocking code wrapped with `Schedulers.boundedElastic()`
- [ ] `switchIfEmpty` fallbacks wrapped in `Mono.defer()` when eager
- [ ] Error handling at every external call (WebClient, R2DBC)
- [ ] Retry with backoff for transient failures
- [ ] Timeouts on all WebClient calls
- [ ] R2DBC connection pool configured appropriately
- [ ] Context propagation configured for tracing/MDC
- [ ] StepVerifier tests for all reactive service methods
- [ ] WebTestClient integration tests for endpoints
- [ ] Backpressure strategy defined for Flux endpoints
- [ ] No shared mutable state without proper synchronization