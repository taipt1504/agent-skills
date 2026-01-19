---
name: java-spring-reactive-expert
description: Expert guidance for high-performance reactive Java with Spring WebFlux, Project Reactor, and reactive data access patterns
version: 1.0.0
triggers:
  - spring webflux
  - java reactive
  - reactor
  - mono flux
  - reactive spring
  - /reactive-java
  - r2dbc
  - reactive mongodb
  - webclient
  - reactive security
tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
references:
  - references/webflux-patterns.md
  - references/reactive-security.md
  - references/reactive-data-access.md
  - references/performance-optimization.md
scripts:
  - scripts/analyze-blocking-calls.py
  - scripts/benchmark-reactive.sh
---

# Java Spring Reactive Expert

## Mục đích

Expert skill cho reactive programming trong Spring ecosystem, bao gồm:
- Spring WebFlux và Project Reactor
- Reactive data access (R2DBC, MongoDB, Redis)
- Reactive security patterns
- Performance optimization và production-ready patterns
- Clean code practices cho reactive code

## Khi nào sử dụng

**Sử dụng skill này khi:**
- Xây dựng REST APIs với Spring WebFlux
- Cần non-blocking I/O cho high concurrency
- Làm việc với reactive databases (R2DBC, reactive MongoDB)
- Implement WebSocket hoặc Server-Sent Events
- Sử dụng WebClient cho HTTP calls
- Cần reactive security patterns
- Optimize performance cho reactive applications
- Debug và test reactive code

**Không sử dụng khi:**
- Application chủ yếu CPU-bound (không có I/O wait)
- Team không familiar với reactive concepts
- Cần blocking operations không thể tránh được
- Simple CRUD với low concurrency
- Legacy integration yêu cầu blocking APIs

## Core Reactive Principles

### Reactive Streams Specification

Reactive Streams là specification chuẩn cho asynchronous stream processing với non-blocking backpressure:

```java
// 4 interfaces cốt lõi
public interface Publisher<T> {
    void subscribe(Subscriber<? super T> s);
}

public interface Subscriber<T> {
    void onSubscribe(Subscription s);
    void onNext(T t);
    void onError(Throwable t);
    void onComplete();
}

public interface Subscription {
    void request(long n);
    void cancel();
}

public interface Processor<T, R> extends Subscriber<T>, Publisher<R> {
}
```

### Project Reactor Fundamentals

#### Mono - 0 hoặc 1 element

```java
// Tạo Mono
Mono<String> empty = Mono.empty();
Mono<String> just = Mono.just("Hello");
Mono<String> fromSupplier = Mono.fromSupplier(() -> expensiveOperation());
Mono<String> fromCallable = Mono.fromCallable(() -> blockingCall());
Mono<String> defer = Mono.defer(() -> Mono.just(dynamicValue()));

// Error handling
Mono<String> error = Mono.error(new RuntimeException("Error"));
Mono<String> withFallback = mono
    .onErrorReturn("default")
    .onErrorResume(e -> Mono.just("fallback"))
    .onErrorMap(e -> new CustomException(e));

// Transformations
Mono<Integer> mapped = mono.map(String::length);
Mono<User> flatMapped = mono.flatMap(id -> userRepository.findById(id));

// Conditional
Mono<String> filtered = mono.filter(s -> s.length() > 5);
Mono<String> defaultIfEmpty = mono.defaultIfEmpty("default");
Mono<String> switchIfEmpty = mono.switchIfEmpty(Mono.just("alternative"));
```

#### Flux - 0 to N elements

```java
// Tạo Flux
Flux<Integer> range = Flux.range(1, 10);
Flux<String> fromIterable = Flux.fromIterable(list);
Flux<String> fromArray = Flux.fromArray(array);
Flux<Long> interval = Flux.interval(Duration.ofSeconds(1));
Flux<String> generate = Flux.generate(
    () -> 0,
    (state, sink) -> {
        sink.next("Value " + state);
        if (state == 10) sink.complete();
        return state + 1;
    }
);

// Flux.create cho async sources
Flux<String> create = Flux.create(sink -> {
    eventSource.onEvent(event -> sink.next(event));
    eventSource.onComplete(() -> sink.complete());
    eventSource.onError(e -> sink.error(e));
});

// Combining
Flux<String> merged = Flux.merge(flux1, flux2);
Flux<String> concat = Flux.concat(flux1, flux2);
Flux<Tuple2<String, Integer>> zipped = Flux.zip(flux1, flux2);
Flux<String> combined = flux1.concatWith(flux2);

// Filtering
Flux<Integer> filtered = flux.filter(i -> i > 5);
Flux<Integer> distinct = flux.distinct();
Flux<Integer> take = flux.take(5);
Flux<Integer> skip = flux.skip(3);

// Grouping
Flux<GroupedFlux<String, User>> grouped = userFlux
    .groupBy(User::getDepartment);

// Windowing và Buffering
Flux<List<Integer>> buffered = flux.buffer(10);
Flux<Flux<Integer>> windowed = flux.window(Duration.ofSeconds(5));
```

### Backpressure Handling

```java
// Backpressure strategies
Flux<Integer> onBackpressureBuffer = flux
    .onBackpressureBuffer(100, BufferOverflowStrategy.DROP_OLDEST);

Flux<Integer> onBackpressureDrop = flux
    .onBackpressureDrop(dropped -> log.warn("Dropped: {}", dropped));

Flux<Integer> onBackpressureLatest = flux.onBackpressureLatest();

Flux<Integer> onBackpressureError = flux.onBackpressureError();

// Request control
flux.subscribe(new BaseSubscriber<Integer>() {
    @Override
    protected void hookOnSubscribe(Subscription subscription) {
        request(10); // Request 10 items initially
    }

    @Override
    protected void hookOnNext(Integer value) {
        process(value);
        request(1); // Request 1 more after processing
    }
});

// LimitRate operator
Flux<Integer> limited = flux.limitRate(100); // Prefetch 100, replenish at 75%
Flux<Integer> limitedLow = flux.limitRate(100, 50); // Custom low tide
```

### Schedulers và Threading Model

```java
// Available Schedulers
Schedulers.immediate();           // Current thread
Schedulers.single();             // Single reusable thread
Schedulers.parallel();           // Fixed pool (CPU cores)
Schedulers.boundedElastic();     // Bounded elastic pool for blocking
Schedulers.fromExecutor(exec);   // Custom executor

// publishOn - affects downstream operators
Flux<String> publishOn = flux
    .map(this::cpuWork)           // Runs on original thread
    .publishOn(Schedulers.parallel())
    .map(this::moreCpuWork);      // Runs on parallel scheduler

// subscribeOn - affects upstream subscription
Mono<String> subscribeOn = Mono
    .fromCallable(() -> blockingCall())
    .subscribeOn(Schedulers.boundedElastic());

// Best practices
@Service
public class ReactiveService {

    public Mono<String> processWithBlocking(String input) {
        return Mono.fromCallable(() -> blockingLibrary.process(input))
            .subscribeOn(Schedulers.boundedElastic()); // Offload blocking
    }

    public Flux<Result> parallelProcess(List<String> items) {
        return Flux.fromIterable(items)
            .parallel()
            .runOn(Schedulers.parallel())
            .map(this::heavyComputation)
            .sequential();
    }
}
```

### Hot vs Cold Publishers

```java
// Cold Publisher - mỗi subscriber nhận full sequence
Flux<Integer> cold = Flux.range(1, 5);
cold.subscribe(i -> System.out.println("Subscriber 1: " + i));
cold.subscribe(i -> System.out.println("Subscriber 2: " + i));
// Cả 2 subscribers đều nhận 1, 2, 3, 4, 5

// Hot Publisher - subscribers share sequence
Sinks.Many<String> sink = Sinks.many().multicast().onBackpressureBuffer();
Flux<String> hot = sink.asFlux();

hot.subscribe(s -> System.out.println("Sub 1: " + s));
sink.tryEmitNext("A");
hot.subscribe(s -> System.out.println("Sub 2: " + s));
sink.tryEmitNext("B");
// Sub 1 nhận A, B; Sub 2 chỉ nhận B

// ConnectableFlux - controlled hot publisher
ConnectableFlux<Long> connectable = Flux.interval(Duration.ofMillis(100))
    .publish();

connectable.subscribe(i -> System.out.println("Sub 1: " + i));
connectable.subscribe(i -> System.out.println("Sub 2: " + i));
connectable.connect(); // Start emitting

// Auto-connect
Flux<Long> autoConnect = Flux.interval(Duration.ofMillis(100))
    .publish()
    .autoConnect(2); // Connect when 2 subscribers

// RefCount - disconnect when no subscribers
Flux<Long> refCount = Flux.interval(Duration.ofMillis(100))
    .publish()
    .refCount(2, Duration.ofSeconds(1));

// Sinks API (modern way to create hot publishers)
Sinks.One<String> one = Sinks.one();
Sinks.Many<String> unicast = Sinks.many().unicast().onBackpressureBuffer();
Sinks.Many<String> multicast = Sinks.many().multicast().onBackpressureBuffer();
Sinks.Many<String> replay = Sinks.many().replay().limit(10);
```

## Spring WebFlux

### Annotated Controllers

```java
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @GetMapping
    public Flux<UserDto> getAllUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return userService.findAll(PageRequest.of(page, size))
            .map(UserMapper::toDto);
    }

    @GetMapping("/{id}")
    public Mono<ResponseEntity<UserDto>> getUser(@PathVariable String id) {
        return userService.findById(id)
            .map(UserMapper::toDto)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserDto> createUser(@Valid @RequestBody Mono<CreateUserRequest> request) {
        return request
            .flatMap(userService::create)
            .map(UserMapper::toDto);
    }

    @PutMapping("/{id}")
    public Mono<ResponseEntity<UserDto>> updateUser(
            @PathVariable String id,
            @Valid @RequestBody Mono<UpdateUserRequest> request) {
        return request
            .flatMap(req -> userService.update(id, req))
            .map(UserMapper::toDto)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteUser(@PathVariable String id) {
        return userService.deleteById(id);
    }

    // Streaming response
    @GetMapping(value = "/stream", produces = MediaType.APPLICATION_NDJSON_VALUE)
    public Flux<UserDto> streamUsers() {
        return userService.findAllStream()
            .map(UserMapper::toDto);
    }
}
```

### Functional Endpoints

```java
@Configuration
public class UserRouter {

    @Bean
    public RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .path("/api/users", builder -> builder
                .GET("", handler::getAllUsers)
                .GET("/{id}", handler::getUser)
                .POST("", handler::createUser)
                .PUT("/{id}", handler::updateUser)
                .DELETE("/{id}", handler::deleteUser)
                .GET("/stream", accept(MediaType.APPLICATION_NDJSON), handler::streamUsers)
            )
            .filter(this::errorHandlingFilter)
            .build();
    }

    private Mono<ServerResponse> errorHandlingFilter(
            ServerRequest request,
            HandlerFunction<ServerResponse> next) {
        return next.handle(request)
            .onErrorResume(ValidationException.class, e ->
                ServerResponse.badRequest()
                    .bodyValue(new ErrorResponse(e.getMessage())))
            .onErrorResume(NotFoundException.class, e ->
                ServerResponse.notFound().build());
    }
}

@Component
@RequiredArgsConstructor
public class UserHandler {

    private final UserService userService;
    private final Validator validator;

    public Mono<ServerResponse> getAllUsers(ServerRequest request) {
        int page = request.queryParam("page").map(Integer::parseInt).orElse(0);
        int size = request.queryParam("size").map(Integer::parseInt).orElse(20);

        return ServerResponse.ok()
            .contentType(MediaType.APPLICATION_JSON)
            .body(userService.findAll(PageRequest.of(page, size))
                .map(UserMapper::toDto), UserDto.class);
    }

    public Mono<ServerResponse> getUser(ServerRequest request) {
        String id = request.pathVariable("id");
        return userService.findById(id)
            .flatMap(user -> ServerResponse.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(UserMapper.toDto(user)))
            .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> createUser(ServerRequest request) {
        return request.bodyToMono(CreateUserRequest.class)
            .doOnNext(this::validate)
            .flatMap(userService::create)
            .flatMap(user -> ServerResponse
                .created(URI.create("/api/users/" + user.getId()))
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(UserMapper.toDto(user)));
    }

    public Mono<ServerResponse> updateUser(ServerRequest request) {
        String id = request.pathVariable("id");
        return request.bodyToMono(UpdateUserRequest.class)
            .doOnNext(this::validate)
            .flatMap(req -> userService.update(id, req))
            .flatMap(user -> ServerResponse.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(UserMapper.toDto(user)))
            .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> deleteUser(ServerRequest request) {
        String id = request.pathVariable("id");
        return userService.deleteById(id)
            .then(ServerResponse.noContent().build());
    }

    public Mono<ServerResponse> streamUsers(ServerRequest request) {
        return ServerResponse.ok()
            .contentType(MediaType.APPLICATION_NDJSON)
            .body(userService.findAllStream().map(UserMapper::toDto), UserDto.class);
    }

    private <T> void validate(T object) {
        var violations = validator.validate(object);
        if (!violations.isEmpty()) {
            throw new ValidationException(violations);
        }
    }
}
```

### WebClient for Non-Blocking HTTP

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient webClient(WebClient.Builder builder) {
        return builder
            .baseUrl("https://api.example.com")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .filter(logRequest())
            .filter(logResponse())
            .filter(retryFilter())
            .codecs(configurer -> configurer
                .defaultCodecs()
                .maxInMemorySize(16 * 1024 * 1024)) // 16MB
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

    private ExchangeFilterFunction retryFilter() {
        return (request, next) -> next.exchange(request)
            .flatMap(response -> {
                if (response.statusCode().is5xxServerError()) {
                    return response.createException().flatMap(Mono::error);
                }
                return Mono.just(response);
            })
            .retryWhen(Retry.backoff(3, Duration.ofMillis(100))
                .filter(e -> e instanceof WebClientResponseException.ServiceUnavailable));
    }
}

@Service
@RequiredArgsConstructor
public class ExternalApiClient {

    private final WebClient webClient;

    public Mono<UserProfile> getUserProfile(String userId) {
        return webClient.get()
            .uri("/users/{id}/profile", userId)
            .header("X-Request-Id", UUID.randomUUID().toString())
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError, response ->
                response.bodyToMono(ErrorResponse.class)
                    .flatMap(error -> Mono.error(new ClientException(error))))
            .onStatus(HttpStatusCode::is5xxServerError, response ->
                Mono.error(new ServerException("External service error")))
            .bodyToMono(UserProfile.class)
            .timeout(Duration.ofSeconds(5))
            .retryWhen(Retry.backoff(3, Duration.ofMillis(100))
                .maxBackoff(Duration.ofSeconds(2))
                .filter(this::isRetryable));
    }

    public Flux<Event> streamEvents(String topic) {
        return webClient.get()
            .uri("/events/stream?topic={topic}", topic)
            .accept(MediaType.APPLICATION_NDJSON)
            .retrieve()
            .bodyToFlux(Event.class);
    }

    public Mono<Response> postWithBody(RequestBody body) {
        return webClient.post()
            .uri("/process")
            .bodyValue(body)
            .exchangeToMono(response -> {
                if (response.statusCode().is2xxSuccessful()) {
                    return response.bodyToMono(Response.class);
                } else if (response.statusCode().is4xxClientError()) {
                    return response.bodyToMono(ErrorResponse.class)
                        .flatMap(error -> Mono.error(new ClientException(error)));
                }
                return response.createException().flatMap(Mono::error);
            });
    }

    public Mono<Void> uploadFile(FilePart file) {
        return webClient.post()
            .uri("/upload")
            .contentType(MediaType.MULTIPART_FORM_DATA)
            .body(BodyInserters.fromMultipartData("file", file))
            .retrieve()
            .bodyToMono(Void.class);
    }

    private boolean isRetryable(Throwable throwable) {
        return throwable instanceof WebClientResponseException.ServiceUnavailable
            || throwable instanceof java.net.ConnectException
            || throwable instanceof java.util.concurrent.TimeoutException;
    }
}
```

### Server-Sent Events (SSE)

```java
@RestController
@RequestMapping("/api/events")
@RequiredArgsConstructor
public class SSEController {

    private final EventService eventService;

    @GetMapping(produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<EventData>> streamEvents() {
        return eventService.getEventStream()
            .map(event -> ServerSentEvent.<EventData>builder()
                .id(event.getId())
                .event(event.getType())
                .data(event.getData())
                .retry(Duration.ofSeconds(5))
                .build());
    }

    @GetMapping(value = "/notifications/{userId}",
                produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<Notification>> userNotifications(
            @PathVariable String userId) {

        Flux<ServerSentEvent<Notification>> notifications = eventService
            .getNotifications(userId)
            .map(n -> ServerSentEvent.<Notification>builder()
                .event("notification")
                .data(n)
                .build());

        // Heartbeat to keep connection alive
        Flux<ServerSentEvent<Notification>> heartbeat = Flux
            .interval(Duration.ofSeconds(30))
            .map(i -> ServerSentEvent.<Notification>builder()
                .event("heartbeat")
                .comment("keep-alive")
                .build());

        return Flux.merge(notifications, heartbeat);
    }
}

@Service
public class EventService {

    private final Sinks.Many<Event> eventSink = Sinks.many()
        .multicast()
        .onBackpressureBuffer(1000);

    public void publishEvent(Event event) {
        eventSink.tryEmitNext(event);
    }

    public Flux<Event> getEventStream() {
        return eventSink.asFlux();
    }

    public Flux<Notification> getNotifications(String userId) {
        return eventSink.asFlux()
            .filter(event -> event.getUserId().equals(userId))
            .map(this::toNotification);
    }
}
```

### WebSocket Integration

```java
@Configuration
@EnableWebFlux
public class WebSocketConfig {

    @Bean
    public HandlerMapping webSocketMapping(ChatWebSocketHandler handler) {
        Map<String, WebSocketHandler> map = new HashMap<>();
        map.put("/ws/chat", handler);

        SimpleUrlHandlerMapping mapping = new SimpleUrlHandlerMapping();
        mapping.setUrlMap(map);
        mapping.setOrder(-1);
        return mapping;
    }

    @Bean
    public WebSocketHandlerAdapter handlerAdapter() {
        return new WebSocketHandlerAdapter();
    }
}

@Component
@RequiredArgsConstructor
@Slf4j
public class ChatWebSocketHandler implements WebSocketHandler {

    private final ChatService chatService;
    private final ObjectMapper objectMapper;

    @Override
    public Mono<Void> handle(WebSocketSession session) {
        String sessionId = session.getId();

        // Incoming messages
        Flux<ChatMessage> incoming = session.receive()
            .map(WebSocketMessage::getPayloadAsText)
            .flatMap(this::parseMessage)
            .doOnNext(msg -> chatService.handleMessage(sessionId, msg))
            .doOnError(e -> log.error("Error processing message", e));

        // Outgoing messages
        Flux<WebSocketMessage> outgoing = chatService.getMessages(sessionId)
            .map(this::toJson)
            .map(session::textMessage);

        return session.send(outgoing)
            .and(incoming.then())
            .doFinally(signal -> chatService.disconnect(sessionId));
    }

    private Mono<ChatMessage> parseMessage(String json) {
        return Mono.fromCallable(() -> objectMapper.readValue(json, ChatMessage.class))
            .onErrorResume(e -> {
                log.warn("Failed to parse message: {}", json);
                return Mono.empty();
            });
    }

    private String toJson(ChatMessage message) {
        try {
            return objectMapper.writeValueAsString(message);
        } catch (JsonProcessingException e) {
            throw new RuntimeException(e);
        }
    }
}

@Service
public class ChatService {

    private final Map<String, Sinks.Many<ChatMessage>> sessions =
        new ConcurrentHashMap<>();

    public void handleMessage(String sessionId, ChatMessage message) {
        // Broadcast to all sessions
        sessions.values().forEach(sink -> sink.tryEmitNext(message));
    }

    public Flux<ChatMessage> getMessages(String sessionId) {
        Sinks.Many<ChatMessage> sink = Sinks.many().multicast().onBackpressureBuffer();
        sessions.put(sessionId, sink);
        return sink.asFlux();
    }

    public void disconnect(String sessionId) {
        Sinks.Many<ChatMessage> sink = sessions.remove(sessionId);
        if (sink != null) {
            sink.tryEmitComplete();
        }
    }
}
```

### Error Handling Patterns

```java
// Global error handling
@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ValidationException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Mono<ErrorResponse> handleValidation(ValidationException ex) {
        return Mono.just(ErrorResponse.builder()
            .code("VALIDATION_ERROR")
            .message(ex.getMessage())
            .details(ex.getViolations())
            .timestamp(Instant.now())
            .build());
    }

    @ExceptionHandler(NotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Mono<ErrorResponse> handleNotFound(NotFoundException ex) {
        return Mono.just(ErrorResponse.builder()
            .code("NOT_FOUND")
            .message(ex.getMessage())
            .timestamp(Instant.now())
            .build());
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public Mono<ErrorResponse> handleGeneral(Exception ex) {
        log.error("Unhandled exception", ex);
        return Mono.just(ErrorResponse.builder()
            .code("INTERNAL_ERROR")
            .message("An unexpected error occurred")
            .timestamp(Instant.now())
            .build());
    }
}

// WebExceptionHandler for functional endpoints
@Component
@Order(-2)
public class GlobalWebExceptionHandler implements WebExceptionHandler {

    private final ObjectMapper objectMapper;

    @Override
    public Mono<Void> handle(ServerWebExchange exchange, Throwable ex) {
        ServerHttpResponse response = exchange.getResponse();

        if (ex instanceof ValidationException) {
            response.setStatusCode(HttpStatus.BAD_REQUEST);
        } else if (ex instanceof NotFoundException) {
            response.setStatusCode(HttpStatus.NOT_FOUND);
        } else {
            response.setStatusCode(HttpStatus.INTERNAL_SERVER_ERROR);
        }

        response.getHeaders().setContentType(MediaType.APPLICATION_JSON);

        ErrorResponse error = ErrorResponse.builder()
            .code(determineErrorCode(ex))
            .message(ex.getMessage())
            .timestamp(Instant.now())
            .build();

        return response.writeWith(Mono.fromCallable(() -> {
            byte[] bytes = objectMapper.writeValueAsBytes(error);
            return response.bufferFactory().wrap(bytes);
        }));
    }
}

// Operator-level error handling
@Service
public class ResilientService {

    public Mono<Result> processWithErrorHandling(Request request) {
        return doProcess(request)
            // Transform specific errors
            .onErrorMap(IOException.class, e ->
                new ServiceException("IO error", e))
            // Fallback for specific errors
            .onErrorResume(TimeoutException.class, e ->
                getCachedResult(request))
            // Default fallback
            .onErrorReturn(Result.empty())
            // Log and rethrow
            .doOnError(e -> log.error("Processing failed", e));
    }

    public Flux<Item> processStreamWithErrors(Flux<Item> items) {
        return items
            .flatMap(item -> processItem(item)
                // Continue stream on error
                .onErrorResume(e -> {
                    log.warn("Failed to process item: {}", item.getId(), e);
                    return Mono.empty();
                }))
            // Or use onErrorContinue (use carefully!)
            .onErrorContinue((e, item) ->
                log.warn("Error processing: {}", item, e));
    }
}
```

## Design Patterns cho Reactive

### Repository Pattern

```java
public interface ReactiveUserRepository {
    Mono<User> findById(String id);
    Flux<User> findAll();
    Flux<User> findByDepartment(String department);
    Mono<User> save(User user);
    Mono<Void> deleteById(String id);
    Mono<Boolean> existsById(String id);
}

@Repository
@RequiredArgsConstructor
public class R2dbcUserRepository implements ReactiveUserRepository {

    private final R2dbcEntityTemplate template;
    private final DatabaseClient databaseClient;

    @Override
    public Mono<User> findById(String id) {
        return template.selectOne(
            Query.query(Criteria.where("id").is(id)),
            User.class
        );
    }

    @Override
    public Flux<User> findAll() {
        return template.select(User.class).all();
    }

    @Override
    public Flux<User> findByDepartment(String department) {
        return databaseClient
            .sql("SELECT * FROM users WHERE department = :dept")
            .bind("dept", department)
            .map((row, metadata) -> mapToUser(row))
            .all();
    }

    @Override
    public Mono<User> save(User user) {
        if (user.getId() == null) {
            user.setId(UUID.randomUUID().toString());
            user.setCreatedAt(Instant.now());
            return template.insert(user);
        }
        user.setUpdatedAt(Instant.now());
        return template.update(user);
    }

    @Override
    public Mono<Void> deleteById(String id) {
        return template.delete(
            Query.query(Criteria.where("id").is(id)),
            User.class
        ).then();
    }

    @Override
    public Mono<Boolean> existsById(String id) {
        return template.exists(
            Query.query(Criteria.where("id").is(id)),
            User.class
        );
    }
}
```

### Service Layer Pattern

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class UserService {

    private final ReactiveUserRepository userRepository;
    private final ReactiveRoleRepository roleRepository;
    private final NotificationService notificationService;
    private final CacheService cacheService;

    @Transactional
    public Mono<User> createUser(CreateUserRequest request) {
        return validateRequest(request)
            .then(checkDuplicate(request.getEmail()))
            .then(buildUser(request))
            .flatMap(userRepository::save)
            .flatMap(this::assignDefaultRole)
            .doOnSuccess(user -> log.info("Created user: {}", user.getId()))
            .flatMap(user -> notificationService.sendWelcomeEmail(user)
                .thenReturn(user))
            .doOnError(e -> log.error("Failed to create user", e));
    }

    public Mono<User> getUserById(String id) {
        return cacheService.get("user:" + id, User.class)
            .switchIfEmpty(userRepository.findById(id)
                .flatMap(user -> cacheService.put("user:" + id, user)
                    .thenReturn(user)));
    }

    @Transactional
    public Mono<User> updateUser(String id, UpdateUserRequest request) {
        return userRepository.findById(id)
            .switchIfEmpty(Mono.error(new NotFoundException("User not found")))
            .map(user -> applyUpdates(user, request))
            .flatMap(userRepository::save)
            .flatMap(user -> cacheService.evict("user:" + id)
                .thenReturn(user));
    }

    public Flux<User> findUsersByDepartment(String department) {
        return userRepository.findByDepartment(department)
            .collectList()
            .flatMapMany(users -> {
                if (users.isEmpty()) {
                    return Flux.empty();
                }
                return enrichWithRoles(Flux.fromIterable(users));
            });
    }

    private Flux<User> enrichWithRoles(Flux<User> users) {
        return users.flatMap(user ->
            roleRepository.findByUserId(user.getId())
                .collectList()
                .map(roles -> {
                    user.setRoles(roles);
                    return user;
                }));
    }

    private Mono<Void> validateRequest(CreateUserRequest request) {
        if (request.getEmail() == null || request.getEmail().isBlank()) {
            return Mono.error(new ValidationException("Email is required"));
        }
        return Mono.empty();
    }

    private Mono<Void> checkDuplicate(String email) {
        return userRepository.existsByEmail(email)
            .flatMap(exists -> exists
                ? Mono.error(new DuplicateException("Email already exists"))
                : Mono.empty());
    }
}
```

### Circuit Breaker Pattern (Resilience4j)

```java
@Configuration
public class ResilienceConfig {

    @Bean
    public CircuitBreakerRegistry circuitBreakerRegistry() {
        CircuitBreakerConfig config = CircuitBreakerConfig.custom()
            .failureRateThreshold(50)
            .waitDurationInOpenState(Duration.ofSeconds(30))
            .permittedNumberOfCallsInHalfOpenState(10)
            .slidingWindowSize(100)
            .recordExceptions(IOException.class, TimeoutException.class)
            .ignoreExceptions(ValidationException.class)
            .build();

        return CircuitBreakerRegistry.of(config);
    }

    @Bean
    public RetryRegistry retryRegistry() {
        RetryConfig config = RetryConfig.custom()
            .maxAttempts(3)
            .waitDuration(Duration.ofMillis(500))
            .exponentialBackoff(2, Duration.ofSeconds(5))
            .retryOnException(e -> e instanceof IOException)
            .build();

        return RetryRegistry.of(config);
    }

    @Bean
    public BulkheadRegistry bulkheadRegistry() {
        BulkheadConfig config = BulkheadConfig.custom()
            .maxConcurrentCalls(100)
            .maxWaitDuration(Duration.ofMillis(500))
            .build();

        return BulkheadRegistry.of(config);
    }
}

@Service
@RequiredArgsConstructor
public class ResilientExternalService {

    private final WebClient webClient;
    private final CircuitBreakerRegistry circuitBreakerRegistry;
    private final RetryRegistry retryRegistry;

    public Mono<ExternalData> fetchData(String id) {
        CircuitBreaker circuitBreaker = circuitBreakerRegistry
            .circuitBreaker("external-service");
        Retry retry = retryRegistry.retry("external-service");

        return webClient.get()
            .uri("/data/{id}", id)
            .retrieve()
            .bodyToMono(ExternalData.class)
            .timeout(Duration.ofSeconds(5))
            .transformDeferred(RetryOperator.of(retry))
            .transformDeferred(CircuitBreakerOperator.of(circuitBreaker))
            .onErrorResume(CallNotPermittedException.class, e ->
                getFallbackData(id));
    }

    private Mono<ExternalData> getFallbackData(String id) {
        return Mono.just(ExternalData.fallback(id));
    }
}

// Using annotations
@Service
public class AnnotatedResilientService {

    @CircuitBreaker(name = "backend", fallbackMethod = "fallback")
    @Retry(name = "backend")
    @Bulkhead(name = "backend")
    @TimeLimiter(name = "backend")
    public Mono<String> callBackend(String input) {
        return webClient.get()
            .uri("/api/process?input={input}", input)
            .retrieve()
            .bodyToMono(String.class);
    }

    private Mono<String> fallback(String input, Throwable t) {
        log.warn("Fallback for input: {}, error: {}", input, t.getMessage());
        return Mono.just("fallback-response");
    }
}
```

### Retry Patterns

```java
@Service
public class RetryPatternService {

    public Mono<Result> withFixedRetry(Request request) {
        return process(request)
            .retryWhen(Retry.fixedDelay(3, Duration.ofSeconds(1)));
    }

    public Mono<Result> withExponentialBackoff(Request request) {
        return process(request)
            .retryWhen(Retry.backoff(5, Duration.ofMillis(100))
                .maxBackoff(Duration.ofSeconds(10))
                .jitter(0.5));
    }

    public Mono<Result> withConditionalRetry(Request request) {
        return process(request)
            .retryWhen(Retry.backoff(3, Duration.ofMillis(100))
                .filter(e -> e instanceof RetryableException)
                .onRetryExhaustedThrow((spec, signal) ->
                    new MaxRetriesExceededException(signal.failure())));
    }

    public Mono<Result> withRetryContext(Request request) {
        return process(request)
            .retryWhen(Retry.backoff(3, Duration.ofMillis(100))
                .doBeforeRetry(signal ->
                    log.warn("Retrying attempt {}: {}",
                        signal.totalRetries() + 1,
                        signal.failure().getMessage()))
                .doAfterRetry(signal ->
                    log.info("Retry {} completed", signal.totalRetries())));
    }
}
```

### Timeout Patterns

```java
@Service
public class TimeoutPatternService {

    public Mono<Result> withSimpleTimeout(Request request) {
        return process(request)
            .timeout(Duration.ofSeconds(5));
    }

    public Mono<Result> withTimeoutAndFallback(Request request) {
        return process(request)
            .timeout(Duration.ofSeconds(5), getFallback(request));
    }

    public Mono<Result> withDifferentTimeouts(Request request) {
        return Mono.firstWithSignal(
            process(request),
            Mono.delay(Duration.ofSeconds(5))
                .flatMap(l -> getCachedResult(request))
        );
    }

    public Flux<Item> withPerItemTimeout(Flux<Item> items) {
        return items.flatMap(item ->
            processItem(item)
                .timeout(Duration.ofSeconds(1))
                .onErrorResume(TimeoutException.class, e -> {
                    log.warn("Timeout processing item: {}", item.getId());
                    return Mono.empty();
                }));
    }
}
```

## Clean Code cho Reactive

### Operator Chains Best Practices

```java
// BAD: Nested chains
public Mono<Result> badExample(String id) {
    return userRepository.findById(id)
        .flatMap(user -> {
            return roleRepository.findByUserId(user.getId())
                .flatMap(role -> {
                    return permissionRepository.findByRoleId(role.getId())
                        .map(permission -> {
                            return new Result(user, role, permission);
                        });
                });
        });
}

// GOOD: Flat chains with meaningful variable names
public Mono<Result> goodExample(String id) {
    return userRepository.findById(id)
        .flatMap(this::enrichWithRole)
        .flatMap(this::enrichWithPermissions)
        .map(this::buildResult);
}

private Mono<UserWithRole> enrichWithRole(User user) {
    return roleRepository.findByUserId(user.getId())
        .map(role -> new UserWithRole(user, role));
}

private Mono<UserWithRoleAndPermissions> enrichWithPermissions(UserWithRole uwr) {
    return permissionRepository.findByRoleId(uwr.role().getId())
        .collectList()
        .map(perms -> new UserWithRoleAndPermissions(uwr, perms));
}

// GOOD: Use tuple for multiple values
public Mono<Result> withTuple(String userId) {
    Mono<User> userMono = userRepository.findById(userId);
    Mono<List<Order>> ordersMono = orderRepository.findByUserId(userId).collectList();
    Mono<UserStats> statsMono = statsService.getStats(userId);

    return Mono.zip(userMono, ordersMono, statsMono)
        .map(tuple -> new Result(tuple.getT1(), tuple.getT2(), tuple.getT3()));
}

// GOOD: Use context for passing data through chain
public Mono<Result> withContext(String userId) {
    return userRepository.findById(userId)
        .flatMap(user -> processUser(user)
            .contextWrite(Context.of("userId", userId)));
}
```

### Error Handling Patterns

```java
@Service
@Slf4j
public class CleanErrorHandling {

    // Define custom exceptions
    public static class UserNotFoundException extends RuntimeException {
        public UserNotFoundException(String id) {
            super("User not found: " + id);
        }
    }

    // Use switchIfEmpty for not found
    public Mono<User> findUser(String id) {
        return userRepository.findById(id)
            .switchIfEmpty(Mono.error(() -> new UserNotFoundException(id)));
    }

    // Chain error handling appropriately
    public Mono<ProcessedData> processWithErrorHandling(String id) {
        return findUser(id)
            .flatMap(this::validateUser)
            .flatMap(this::enrichUser)
            .flatMap(this::processUser)
            // Handle specific errors at appropriate level
            .onErrorResume(UserNotFoundException.class, e -> {
                log.debug("User not found, returning empty");
                return Mono.empty();
            })
            .onErrorResume(ValidationException.class, e -> {
                log.warn("Validation failed: {}", e.getMessage());
                return Mono.error(new BadRequestException(e.getMessage()));
            })
            // Log unexpected errors
            .doOnError(e -> log.error("Unexpected error processing user {}", id, e));
    }

    // Create error with context
    public Mono<Result> withErrorContext(Request request) {
        return process(request)
            .onErrorMap(e -> new ProcessingException(
                "Failed to process request: " + request.getId(), e))
            .checkpoint("Processing step"); // Add checkpoint for debugging
    }
}
```

### Testing Reactive Code với StepVerifier

```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private ReactiveUserRepository userRepository;

    @Mock
    private NotificationService notificationService;

    @InjectMocks
    private UserService userService;

    @Test
    void shouldFindUserById() {
        User user = new User("1", "John", "john@example.com");
        when(userRepository.findById("1")).thenReturn(Mono.just(user));

        StepVerifier.create(userService.findById("1"))
            .expectNext(user)
            .verifyComplete();
    }

    @Test
    void shouldReturnEmptyWhenUserNotFound() {
        when(userRepository.findById("1")).thenReturn(Mono.empty());

        StepVerifier.create(userService.findById("1"))
            .verifyComplete();
    }

    @Test
    void shouldHandleError() {
        when(userRepository.findById("1"))
            .thenReturn(Mono.error(new RuntimeException("DB error")));

        StepVerifier.create(userService.findById("1"))
            .expectError(RuntimeException.class)
            .verify();
    }

    @Test
    void shouldEmitMultipleUsers() {
        User user1 = new User("1", "John", "john@example.com");
        User user2 = new User("2", "Jane", "jane@example.com");
        when(userRepository.findAll()).thenReturn(Flux.just(user1, user2));

        StepVerifier.create(userService.findAll())
            .expectNext(user1)
            .expectNext(user2)
            .verifyComplete();
    }

    @Test
    void shouldVerifyWithVirtualTime() {
        Flux<Long> intervalFlux = Flux.interval(Duration.ofSeconds(1)).take(3);

        StepVerifier.withVirtualTime(() -> intervalFlux)
            .expectSubscription()
            .thenAwait(Duration.ofSeconds(3))
            .expectNext(0L, 1L, 2L)
            .verifyComplete();
    }

    @Test
    void shouldVerifyNoEventsDuring() {
        Flux<Long> delayed = Flux.just(1L).delayElements(Duration.ofSeconds(5));

        StepVerifier.withVirtualTime(() -> delayed)
            .expectSubscription()
            .expectNoEvent(Duration.ofSeconds(4))
            .thenAwait(Duration.ofSeconds(1))
            .expectNext(1L)
            .verifyComplete();
    }

    @Test
    void shouldAssertWithCustomConditions() {
        Flux<User> users = userService.findByDepartment("IT");

        StepVerifier.create(users)
            .expectNextMatches(u -> u.getDepartment().equals("IT"))
            .expectNextCount(4)
            .thenConsumeWhile(u -> u.getDepartment().equals("IT"))
            .verifyComplete();
    }

    @Test
    void shouldRecordAndVerify() {
        StepVerifier.create(userService.findAll().take(5))
            .recordWith(ArrayList::new)
            .thenConsumeWhile(u -> true)
            .consumeRecordedWith(users -> {
                assertThat(users).hasSize(5);
                assertThat(users).allMatch(u -> u.getId() != null);
            })
            .verifyComplete();
    }
}
```

### Debugging Techniques

```java
@Service
@Slf4j
public class DebuggableService {

    public Mono<Result> processWithDebugging(Request request) {
        return Mono.just(request)
            // Log with doOn* operators
            .doOnSubscribe(s -> log.debug("Processing started"))
            .doOnNext(r -> log.debug("Processing: {}", r))
            .doOnError(e -> log.error("Processing failed", e))
            .doOnSuccess(r -> log.debug("Processing completed: {}", r))
            .doFinally(signal -> log.debug("Signal: {}", signal))

            // Add checkpoints for stack traces
            .checkpoint("After validation")
            .flatMap(this::validate)
            .checkpoint("After enrichment")
            .flatMap(this::enrich)
            .checkpoint("After processing")
            .flatMap(this::process)

            // Log operator for detailed logging
            .log("ProcessingPipeline", Level.FINE);
    }

    // Enable Hooks for global debugging
    @PostConstruct
    public void enableDebugHooks() {
        // Only in development
        if (isDevelopment()) {
            Hooks.onOperatorDebug();
        }
    }

    // Context propagation for request tracing
    public Mono<Result> withTracing(Request request) {
        String traceId = UUID.randomUUID().toString();

        return process(request)
            .doOnEach(signal -> {
                if (!signal.isOnComplete()) {
                    String ctx = signal.getContextView()
                        .getOrDefault("traceId", "unknown");
                    log.debug("[{}] Signal: {}", ctx, signal.getType());
                }
            })
            .contextWrite(Context.of("traceId", traceId));
    }
}
```

### Context Propagation

```java
@Service
public class ContextPropagationService {

    private static final String USER_CONTEXT_KEY = "user";
    private static final String TRACE_ID_KEY = "traceId";

    public Mono<Result> processWithContext(Request request) {
        return Mono.deferContextual(ctx -> {
            String traceId = ctx.getOrDefault(TRACE_ID_KEY, "unknown");
            User user = ctx.getOrDefault(USER_CONTEXT_KEY, null);

            log.info("[{}] Processing for user: {}", traceId, user);
            return doProcess(request, user);
        });
    }

    public Mono<Result> orchestrate(Request request, User user) {
        return processWithContext(request)
            .flatMap(this::enrichResult)
            .flatMap(this::saveResult)
            .contextWrite(ctx -> ctx
                .put(USER_CONTEXT_KEY, user)
                .put(TRACE_ID_KEY, UUID.randomUUID().toString()));
    }

    // WebFilter for automatic context propagation
    @Component
    public class ContextWebFilter implements WebFilter {

        @Override
        public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
            String traceId = exchange.getRequest().getHeaders()
                .getFirst("X-Trace-Id");
            if (traceId == null) {
                traceId = UUID.randomUUID().toString();
            }

            String finalTraceId = traceId;
            return chain.filter(exchange)
                .contextWrite(ctx -> ctx.put(TRACE_ID_KEY, finalTraceId));
        }
    }

    // MDC integration for logging
    public Mono<Result> withMDC(Request request) {
        return Mono.deferContextual(ctx -> {
            String traceId = ctx.getOrDefault(TRACE_ID_KEY, "unknown");

            return Mono.fromCallable(() -> {
                try (MDC.MDCCloseable ignored = MDC.putCloseable("traceId", traceId)) {
                    return processSync(request);
                }
            }).subscribeOn(Schedulers.boundedElastic());
        });
    }
}
```

## Integration Patterns

### Reactive Kafka

```java
@Configuration
public class KafkaReactiveConfig {

    @Bean
    public ReactiveKafkaProducerTemplate<String, Event> kafkaProducerTemplate(
            KafkaProperties properties) {
        Map<String, Object> props = properties.buildProducerProperties();
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);

        SenderOptions<String, Event> senderOptions = SenderOptions.create(props);
        return new ReactiveKafkaProducerTemplate<>(senderOptions);
    }

    @Bean
    public ReactiveKafkaConsumerTemplate<String, Event> kafkaConsumerTemplate(
            KafkaProperties properties) {
        Map<String, Object> props = properties.buildConsumerProperties();
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, JsonDeserializer.class);
        props.put(JsonDeserializer.TRUSTED_PACKAGES, "*");

        ReceiverOptions<String, Event> receiverOptions = ReceiverOptions
            .<String, Event>create(props)
            .subscription(Collections.singleton("events"))
            .addAssignListener(partitions -> log.info("Assigned: {}", partitions))
            .addRevokeListener(partitions -> log.info("Revoked: {}", partitions));

        return new ReactiveKafkaConsumerTemplate<>(receiverOptions);
    }
}

@Service
@RequiredArgsConstructor
@Slf4j
public class KafkaEventService {

    private final ReactiveKafkaProducerTemplate<String, Event> producer;
    private final ReactiveKafkaConsumerTemplate<String, Event> consumer;

    public Mono<Void> publishEvent(Event event) {
        return producer.send("events", event.getId(), event)
            .doOnSuccess(result -> log.info("Sent event: {} to partition: {}",
                event.getId(), result.recordMetadata().partition()))
            .then();
    }

    public Flux<Event> consumeEvents() {
        return consumer.receiveAutoAck()
            .doOnNext(record -> log.info("Received: key={}, value={}",
                record.key(), record.value()))
            .map(ConsumerRecord::value)
            .doOnError(e -> log.error("Error consuming", e))
            .retryWhen(Retry.backoff(3, Duration.ofSeconds(1)));
    }

    @EventListener(ApplicationStartedEvent.class)
    public void startConsumer() {
        consumeEvents()
            .flatMap(this::processEvent)
            .subscribe(
                result -> log.info("Processed: {}", result),
                error -> log.error("Consumer error", error)
            );
    }
}
```

### Reactive RabbitMQ

```java
@Configuration
public class RabbitReactiveConfig {

    @Bean
    public Mono<Connection> connectionMono(RabbitProperties properties) {
        ConnectionFactory connectionFactory = new ConnectionFactory();
        connectionFactory.setHost(properties.getHost());
        connectionFactory.setPort(properties.getPort());
        connectionFactory.setUsername(properties.getUsername());
        connectionFactory.setPassword(properties.getPassword());
        connectionFactory.useNio();

        return Mono.fromCallable(() -> connectionFactory.newConnection())
            .cache();
    }

    @Bean
    public Sender sender(Mono<Connection> connectionMono) {
        return RabbitFlux.createSender(new SenderOptions()
            .connectionMono(connectionMono));
    }

    @Bean
    public Receiver receiver(Mono<Connection> connectionMono) {
        return RabbitFlux.createReceiver(new ReceiverOptions()
            .connectionMono(connectionMono));
    }
}

@Service
@RequiredArgsConstructor
@Slf4j
public class RabbitEventService {

    private final Sender sender;
    private final Receiver receiver;
    private final ObjectMapper objectMapper;

    public Mono<Void> publishEvent(String queue, Event event) {
        return Mono.fromCallable(() -> objectMapper.writeValueAsBytes(event))
            .flatMap(bytes -> sender.send(Mono.just(
                new OutboundMessage("", queue, bytes)
            )))
            .doOnSuccess(v -> log.info("Published event to {}", queue));
    }

    public Flux<Event> consumeEvents(String queue) {
        return receiver.consumeAutoAck(queue)
            .map(delivery -> {
                try {
                    return objectMapper.readValue(delivery.getBody(), Event.class);
                } catch (IOException e) {
                    throw new RuntimeException("Failed to deserialize", e);
                }
            })
            .doOnNext(event -> log.info("Received event: {}", event.getId()));
    }

    public Flux<Event> consumeWithManualAck(String queue) {
        return receiver.consumeManualAck(queue)
            .flatMap(delivery -> {
                try {
                    Event event = objectMapper.readValue(delivery.getBody(), Event.class);
                    return processEvent(event)
                        .doOnSuccess(v -> delivery.ack())
                        .doOnError(e -> delivery.nack(false))
                        .thenReturn(event);
                } catch (IOException e) {
                    delivery.nack(false);
                    return Mono.error(e);
                }
            });
    }
}
```

### gRPC Reactive

```java
// Proto definition
// service UserService {
//     rpc GetUser(GetUserRequest) returns (User);
//     rpc ListUsers(ListUsersRequest) returns (stream User);
//     rpc CreateUsers(stream CreateUserRequest) returns (CreateUsersResponse);
// }

@GrpcService
@RequiredArgsConstructor
public class ReactiveUserGrpcService extends ReactorUserServiceGrpc.UserServiceImplBase {

    private final UserService userService;
    private final UserMapper mapper;

    @Override
    public Mono<User> getUser(GetUserRequest request) {
        return userService.findById(request.getId())
            .map(mapper::toProto)
            .switchIfEmpty(Mono.error(
                Status.NOT_FOUND
                    .withDescription("User not found: " + request.getId())
                    .asRuntimeException()
            ));
    }

    @Override
    public Flux<User> listUsers(ListUsersRequest request) {
        return userService.findAll(PageRequest.of(
                request.getPage(),
                request.getSize()
            ))
            .map(mapper::toProto);
    }

    @Override
    public Mono<CreateUsersResponse> createUsers(Flux<CreateUserRequest> requests) {
        return requests
            .map(mapper::fromProto)
            .flatMap(userService::create)
            .count()
            .map(count -> CreateUsersResponse.newBuilder()
                .setCreatedCount(count.intValue())
                .build());
    }
}

// gRPC Client
@Component
@RequiredArgsConstructor
public class UserGrpcClient {

    private final ReactorUserServiceGrpc.ReactorUserServiceStub stub;

    public Mono<User> getUser(String id) {
        return stub.getUser(GetUserRequest.newBuilder()
                .setId(id)
                .build())
            .timeout(Duration.ofSeconds(5))
            .onErrorResume(StatusRuntimeException.class, e -> {
                if (e.getStatus().getCode() == Status.Code.NOT_FOUND) {
                    return Mono.empty();
                }
                return Mono.error(e);
            });
    }

    public Flux<User> listUsers(int page, int size) {
        return stub.listUsers(ListUsersRequest.newBuilder()
                .setPage(page)
                .setSize(size)
                .build());
    }
}
```

### GraphQL Reactive

```java
@Controller
@RequiredArgsConstructor
public class UserGraphQLController {

    private final UserService userService;
    private final OrderService orderService;

    @QueryMapping
    public Mono<User> user(@Argument String id) {
        return userService.findById(id);
    }

    @QueryMapping
    public Flux<User> users(
            @Argument int page,
            @Argument int size) {
        return userService.findAll(PageRequest.of(page, size));
    }

    @SchemaMapping(typeName = "User")
    public Flux<Order> orders(User user) {
        return orderService.findByUserId(user.getId());
    }

    @MutationMapping
    public Mono<User> createUser(@Argument CreateUserInput input) {
        return userService.create(input);
    }

    @SubscriptionMapping
    public Flux<UserEvent> userEvents(@Argument String userId) {
        return userService.getEventStream(userId);
    }

    // Batch loading for N+1 prevention
    @BatchMapping
    public Flux<List<Order>> orders(List<User> users) {
        List<String> userIds = users.stream()
            .map(User::getId)
            .toList();

        return orderService.findByUserIds(userIds)
            .collectMultimap(Order::getUserId)
            .flatMapMany(orderMap -> Flux.fromIterable(users)
                .map(user -> orderMap.getOrDefault(user.getId(), List.of())));
    }
}

// GraphQL Configuration
@Configuration
public class GraphQLConfig {

    @Bean
    public RuntimeWiringConfigurer runtimeWiringConfigurer() {
        return wiringBuilder -> wiringBuilder
            .scalar(ExtendedScalars.DateTime)
            .scalar(ExtendedScalars.UUID);
    }

    @Bean
    public DataFetcherExceptionResolver exceptionResolver() {
        return (exception, environment) -> {
            if (exception instanceof NotFoundException) {
                return Mono.just(List.of(GraphqlErrorBuilder.newError()
                    .message(exception.getMessage())
                    .errorType(ErrorType.NOT_FOUND)
                    .path(environment.getExecutionStepInfo().getPath())
                    .build()));
            }
            return Mono.empty();
        };
    }
}
```

## Anti-patterns và Common Mistakes

### Blocking Calls trong Reactive

```java
// BAD: Blocking call trong reactive chain
public Mono<User> badBlockingCall(String id) {
    return userRepository.findById(id)
        .map(user -> {
            // BLOCKING! Gọi service blocking trong map
            String details = blockingService.getDetails(user.getId());
            user.setDetails(details);
            return user;
        });
}

// GOOD: Wrap blocking calls properly
public Mono<User> goodBlockingCall(String id) {
    return userRepository.findById(id)
        .flatMap(user ->
            Mono.fromCallable(() -> blockingService.getDetails(user.getId()))
                .subscribeOn(Schedulers.boundedElastic())
                .map(details -> {
                    user.setDetails(details);
                    return user;
                }));
}

// BAD: block() trong reactive chain
public Mono<Result> badBlock(String id) {
    return userRepository.findById(id)
        .flatMap(user -> {
            // BLOCKING! Never call block() in reactive chain
            Order order = orderRepository.findByUserId(user.getId()).block();
            return Mono.just(new Result(user, order));
        });
}

// GOOD: Keep it reactive
public Mono<Result> goodNoBlock(String id) {
    return userRepository.findById(id)
        .flatMap(user -> orderRepository.findByUserId(user.getId())
            .map(order -> new Result(user, order)));
}

// BAD: Thread.sleep in reactive
public Mono<String> badSleep() {
    return Mono.fromCallable(() -> {
        Thread.sleep(1000); // BLOCKING!
        return "result";
    });
}

// GOOD: Use reactive delay
public Mono<String> goodDelay() {
    return Mono.just("result")
        .delayElement(Duration.ofSeconds(1));
}
```

### Memory Leaks

```java
// BAD: Unbounded buffer
Sinks.Many<Event> badSink = Sinks.many().multicast()
    .onBackpressureBuffer(); // Unbounded - memory leak risk!

// GOOD: Bounded buffer with strategy
Sinks.Many<Event> goodSink = Sinks.many().multicast()
    .onBackpressureBuffer(1000, event ->
        log.warn("Dropped event due to backpressure: {}", event));

// BAD: Not disposing subscriptions
@Service
public class BadService {
    public void startProcessing() {
        eventFlux.subscribe(this::process); // Subscription never disposed!
    }
}

// GOOD: Properly manage subscriptions
@Service
public class GoodService implements DisposableBean {
    private Disposable subscription;

    public void startProcessing() {
        subscription = eventFlux.subscribe(this::process);
    }

    @Override
    public void destroy() {
        if (subscription != null && !subscription.isDisposed()) {
            subscription.dispose();
        }
    }
}

// BAD: Collecting unbounded stream to list
public Mono<List<Event>> badCollect() {
    return infiniteEventStream.collectList(); // Will OOM!
}

// GOOD: Use windowing or pagination
public Flux<List<Event>> goodWindow() {
    return infiniteEventStream
        .buffer(100) // Process in batches
        .delayElements(Duration.ofMillis(100)); // Rate limit
}

// BAD: Not releasing resources
public Flux<String> badResource() {
    return Flux.using(
        () -> openConnection(),
        conn -> queryData(conn),
        conn -> {} // Connection never closed!
    );
}

// GOOD: Properly release resources
public Flux<String> goodResource() {
    return Flux.using(
        () -> openConnection(),
        conn -> queryData(conn),
        conn -> conn.close() // Always close
    );
}
```

### Common Mistakes

```java
// MISTAKE 1: Multiple subscriptions causing duplicate work
Mono<User> userMono = userRepository.findById(id);
userMono.subscribe(u -> log.info("User: {}", u));
userMono.subscribe(u -> sendNotification(u)); // DB called twice!

// FIX: Use cache() for sharing
Mono<User> cachedUserMono = userRepository.findById(id).cache();
cachedUserMono.subscribe(u -> log.info("User: {}", u));
cachedUserMono.subscribe(u -> sendNotification(u)); // DB called once

// MISTAKE 2: Losing context with incorrect operator
public Mono<User> lostContext(String id) {
    return userRepository.findById(id)
        .flatMap(user -> Mono.just(user) // Creates new Mono, loses context
            .contextWrite(ctx -> ctx.put("userId", id)));
}

// FIX: Apply contextWrite at the right place
public Mono<User> preservedContext(String id) {
    return userRepository.findById(id)
        .contextWrite(ctx -> ctx.put("userId", id)); // Applied to chain
}

// MISTAKE 3: Side effects in wrong operator
public Flux<User> wrongSideEffect() {
    return userRepository.findAll()
        .map(user -> {
            auditService.log(user); // Side effect in map - bad!
            return user;
        });
}

// FIX: Use doOnNext for side effects
public Flux<User> correctSideEffect() {
    return userRepository.findAll()
        .doOnNext(user -> auditService.log(user))
        .map(user -> user);
}

// MISTAKE 4: Not handling empty
public Mono<UserDto> ignoresEmpty(String id) {
    return userRepository.findById(id)
        .map(this::toDto); // If empty, map never executes, returns empty
}

// FIX: Handle empty explicitly
public Mono<UserDto> handlesEmpty(String id) {
    return userRepository.findById(id)
        .map(this::toDto)
        .switchIfEmpty(Mono.error(new NotFoundException("User not found")));
}

// MISTAKE 5: Ignoring errors
public Mono<Result> ignoresError(Request request) {
    return process(request)
        .onErrorResume(e -> Mono.empty()); // Silently swallows errors
}

// FIX: Log and handle appropriately
public Mono<Result> handlesError(Request request) {
    return process(request)
        .doOnError(e -> log.error("Processing failed", e))
        .onErrorResume(e -> Mono.error(new ProcessingException("Failed", e)));
}

// MISTAKE 6: Using .then() incorrectly
public Mono<Void> wrongThen(User user) {
    return Mono.just(user)
        .then(sendEmail(user)); // sendEmail might not get user context
}

// FIX: Chain properly
public Mono<Void> correctThen(User user) {
    return Mono.just(user)
        .flatMap(u -> sendEmail(u))
        .then();
}
```

## Production Checklist

### Pre-Production Checklist

```markdown
## Code Quality
- [ ] Không có blocking calls trong reactive chains
- [ ] Tất cả external calls có timeout
- [ ] Error handling đầy đủ với appropriate fallbacks
- [ ] Backpressure được handle properly
- [ ] Resources được cleanup (disposables, connections)
- [ ] No memory leaks (bounded buffers, proper subscriptions)
- [ ] Context propagation cho logging và tracing

## Testing
- [ ] Unit tests với StepVerifier
- [ ] Integration tests với @SpringBootTest
- [ ] Load testing với realistic scenarios
- [ ] Tested với virtual time cho time-based operators
- [ ] Error scenarios tested
- [ ] Timeout scenarios tested

## Performance
- [ ] Connection pool sizing đúng
- [ ] Thread pool sizing đúng
- [ ] Memory limits configured
- [ ] Backpressure strategy phù hợp
- [ ] Caching strategy implemented
- [ ] Database query optimization

## Observability
- [ ] Metrics với Micrometer
- [ ] Distributed tracing với correlation IDs
- [ ] Structured logging
- [ ] Health checks configured
- [ ] Alerting rules defined

## Security
- [ ] Authentication configured
- [ ] Authorization rules applied
- [ ] Input validation
- [ ] Rate limiting
- [ ] CORS configuration

## Resilience
- [ ] Circuit breakers configured
- [ ] Retry policies defined
- [ ] Timeout values set
- [ ] Fallback strategies implemented
- [ ] Graceful degradation

## Configuration
- [ ] Environment-specific configs
- [ ] Secrets management
- [ ] Feature flags nếu cần
- [ ] Logging levels appropriate
```

### Monitoring Configuration

```java
@Configuration
public class ObservabilityConfig {

    @Bean
    public MeterRegistryCustomizer<MeterRegistry> metricsCommonTags() {
        return registry -> registry.config()
            .commonTags("application", "my-reactive-app");
    }

    @Bean
    public TimedAspect timedAspect(MeterRegistry registry) {
        return new TimedAspect(registry);
    }
}

// Application properties for production
// management.endpoints.web.exposure.include=health,info,metrics,prometheus
// management.metrics.tags.application=${spring.application.name}
// management.metrics.distribution.percentiles-histogram.http.server.requests=true

// Health indicators
@Component
public class ReactiveHealthIndicator implements ReactiveHealthIndicator {

    private final DatabaseClient databaseClient;

    @Override
    public Mono<Health> health() {
        return databaseClient.sql("SELECT 1")
            .fetch()
            .first()
            .map(result -> Health.up().build())
            .onErrorResume(e -> Mono.just(Health.down(e).build()))
            .timeout(Duration.ofSeconds(5));
    }
}
```

### Performance Tuning Example

```yaml
# application.yml for production
spring:
  r2dbc:
    pool:
      initial-size: 10
      max-size: 50
      max-idle-time: 30m
      validation-query: SELECT 1

  webflux:
    base-path: /api

server:
  port: 8080
  netty:
    connection-timeout: 5s
    idle-timeout: 60s
    max-keep-alive-requests: 1000

logging:
  level:
    reactor.netty: INFO
    io.r2dbc: INFO
    org.springframework.r2dbc: DEBUG

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true
```

## Workflow khi sử dụng skill này

1. **Analyze requirements**: Đọc code hiện tại và xác định reactive patterns phù hợp
2. **Check for blocking**: Sử dụng script `analyze-blocking-calls.py` để detect blocking calls
3. **Implement patterns**: Áp dụng patterns từ skill này
4. **Test with StepVerifier**: Viết tests cho reactive code
5. **Performance test**: Sử dụng `benchmark-reactive.sh` để benchmark
6. **Production checklist**: Review với production checklist

## Related References

- [WebFlux Patterns](references/webflux-patterns.md) - Chi tiết về WebFlux patterns
- [Reactive Security](references/reactive-security.md) - Security patterns cho reactive
- [Reactive Data Access](references/reactive-data-access.md) - R2DBC, MongoDB, Redis
- [Performance Optimization](references/performance-optimization.md) - Tuning guide
