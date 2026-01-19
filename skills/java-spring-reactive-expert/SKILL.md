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
  - spring boot reactive
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

## Purpose

Expert skill for reactive programming in the Spring ecosystem, including:

- Spring WebFlux and Project Reactor
- Reactive data access (R2DBC, MongoDB, Redis)
- Reactive security patterns
- Performance optimization and production-ready patterns
- Clean code practices for reactive code

## When to Use

**Use this skill when:**
- Building REST APIs with Spring WebFlux
- Needing non-blocking I/O for high concurrency
- Working with reactive databases (R2DBC, reactive MongoDB)
- Implementing WebSocket or Server-Sent Events
- Using WebClient for HTTP calls
- Needing reactive security patterns
- Optimizing performance for reactive applications
- Debugging and testing reactive code

**Do NOT use when:**
- Application is primarily CPU-bound (no I/O wait)
- Team is not familiar with reactive concepts
- Blocking operations cannot be avoided
- Simple CRUD with low concurrency
- Legacy integration requires blocking APIs

---

## Core Reactive Principles

### Reactive Streams Specification

Reactive Streams is the standard specification for asynchronous stream processing with non-blocking backpressure:

```java
// 4 core interfaces
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

#### Mono - 0 or 1 element

```java
// Create Mono
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
// Create Flux
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

// Flux.create for async sources
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

// Windowing and Buffering
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

### Schedulers and Threading Model

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
// Cold Publisher - each subscriber receives full sequence
Flux<Integer> cold = Flux.range(1, 5);
cold.subscribe(i -> System.out.println("Subscriber 1: " + i));
cold.subscribe(i -> System.out.println("Subscriber 2: " + i));
// Both subscribers receive 1, 2, 3, 4, 5

// Hot Publisher - subscribers share sequence
Sinks.Many<String> sink = Sinks.many().multicast().onBackpressureBuffer();
Flux<String> hot = sink.asFlux();

hot.subscribe(s -> System.out.println("Sub 1: " + s));
sink.tryEmitNext("A");
hot.subscribe(s -> System.out.println("Sub 2: " + s));
sink.tryEmitNext("B");
// Sub 1 receives A, B; Sub 2 only receives B

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
            .onErrorMap(IOException.class, e -> new ClientException(e))
            // Return default value on error
            .onErrorReturn(ClientException.class, Result.defaultVal())
            // Switch to fallback flow
            .onErrorResume(TimeoutException.class, e -> processFromBackup(request))
            // Retry with backoff
            .retryWhen(Retry.backoff(3, Duration.ofMillis(100))
                .filter(e -> e instanceof TimeoutException));
    }
}
```
