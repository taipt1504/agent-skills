# WebFlux Patterns Reference

## Table of Contents
- [Router Function Patterns](#router-function-patterns)
- [Handler Patterns](#handler-patterns)
- [WebClient Advanced Patterns](#webclient-advanced-patterns)
- [SSE và WebSocket Patterns](#sse-và-websocket-patterns)
- [Request/Response Processing](#requestresponse-processing)
- [Error Handling Strategies](#error-handling-strategies)
- [Filter Patterns](#filter-patterns)

## Router Function Patterns

### Nested Routes

```java
@Configuration
public class ApiRouter {

    @Bean
    public RouterFunction<ServerResponse> apiRoutes(
            UserHandler userHandler,
            OrderHandler orderHandler,
            ProductHandler productHandler) {

        return RouterFunctions.route()
            .path("/api/v1", builder -> builder
                .nest(path("/users"), this::userRoutes)
                .nest(path("/orders"), this::orderRoutes)
                .nest(path("/products"), this::productRoutes)
            )
            .filter(this::loggingFilter)
            .filter(this::errorHandlingFilter)
            .build();
    }

    private RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .GET("", handler::listUsers)
            .GET("/{id}", handler::getUser)
            .POST("", contentType(APPLICATION_JSON), handler::createUser)
            .PUT("/{id}", contentType(APPLICATION_JSON), handler::updateUser)
            .DELETE("/{id}", handler::deleteUser)
            .nest(path("/{userId}/orders"), builder -> builder
                .GET("", handler::getUserOrders)
                .GET("/{orderId}", handler::getUserOrder)
            )
            .build();
    }

    private RequestPredicate path(String pattern) {
        return RequestPredicates.path(pattern);
    }

    private RequestPredicate contentType(MediaType mediaType) {
        return RequestPredicates.contentType(mediaType);
    }
}
```

### Conditional Routes

```java
@Bean
public RouterFunction<ServerResponse> conditionalRoutes(
        FeatureFlagService featureFlags,
        LegacyHandler legacyHandler,
        NewHandler newHandler) {

    return RouterFunctions.route()
        .path("/api/process", builder -> {
            if (featureFlags.isEnabled("new-processor")) {
                builder.POST("", newHandler::process);
            } else {
                builder.POST("", legacyHandler::process);
            }
        })
        .build();
}

// Dynamic routing based on request
@Bean
public RouterFunction<ServerResponse> dynamicRoutes() {
    return RouterFunctions.route()
        .route(
            RequestPredicates.GET("/api/data")
                .and(request -> request.headers().header("X-Version").contains("v2")),
            this::handleV2
        )
        .route(
            RequestPredicates.GET("/api/data"),
            this::handleV1
        )
        .build();
}
```

### Route Composition

```java
@Configuration
public class ComposedRouterConfig {

    @Bean
    public RouterFunction<ServerResponse> composedRoutes(
            List<ApiRouterContributor> contributors) {

        RouterFunction<ServerResponse> routes = RouterFunctions.route()
            .GET("/health", request -> ServerResponse.ok().bodyValue("OK"))
            .build();

        for (ApiRouterContributor contributor : contributors) {
            routes = routes.and(contributor.routes());
        }

        return routes;
    }
}

public interface ApiRouterContributor {
    RouterFunction<ServerResponse> routes();
}

@Component
@Order(1)
public class UserApiContributor implements ApiRouterContributor {

    private final UserHandler handler;

    @Override
    public RouterFunction<ServerResponse> routes() {
        return RouterFunctions.route()
            .path("/api/users", builder -> builder
                .GET("", handler::list)
                .GET("/{id}", handler::get)
                .POST("", handler::create)
            )
            .build();
    }
}
```

## Handler Patterns

### Request Validation Handler

```java
@Component
@RequiredArgsConstructor
public class ValidatingHandler {

    private final Validator validator;
    private final UserService userService;

    public Mono<ServerResponse> createUser(ServerRequest request) {
        return request.bodyToMono(CreateUserRequest.class)
            .flatMap(this::validate)
            .flatMap(userService::create)
            .flatMap(user -> ServerResponse
                .created(URI.create("/api/users/" + user.getId()))
                .bodyValue(user))
            .onErrorResume(ValidationException.class, this::handleValidationError);
    }

    private <T> Mono<T> validate(T object) {
        Set<ConstraintViolation<T>> violations = validator.validate(object);
        if (violations.isEmpty()) {
            return Mono.just(object);
        }

        Map<String, String> errors = violations.stream()
            .collect(Collectors.toMap(
                v -> v.getPropertyPath().toString(),
                ConstraintViolation::getMessage,
                (a, b) -> a + "; " + b
            ));

        return Mono.error(new ValidationException(errors));
    }

    private Mono<ServerResponse> handleValidationError(ValidationException ex) {
        return ServerResponse.badRequest()
            .bodyValue(ErrorResponse.builder()
                .code("VALIDATION_ERROR")
                .message("Validation failed")
                .details(ex.getErrors())
                .build());
    }
}
```

### Pagination Handler

```java
@Component
public class PaginatedHandler {

    private static final int DEFAULT_PAGE = 0;
    private static final int DEFAULT_SIZE = 20;
    private static final int MAX_SIZE = 100;

    public Mono<ServerResponse> listUsers(ServerRequest request) {
        int page = request.queryParam("page")
            .map(Integer::parseInt)
            .orElse(DEFAULT_PAGE);

        int size = request.queryParam("size")
            .map(Integer::parseInt)
            .map(s -> Math.min(s, MAX_SIZE))
            .orElse(DEFAULT_SIZE);

        String sortBy = request.queryParam("sort").orElse("createdAt");
        String direction = request.queryParam("dir").orElse("desc");

        Sort sort = direction.equalsIgnoreCase("asc")
            ? Sort.by(sortBy).ascending()
            : Sort.by(sortBy).descending();

        PageRequest pageRequest = PageRequest.of(page, size, sort);

        return userService.findAll(pageRequest)
            .collectList()
            .zipWith(userService.count())
            .flatMap(tuple -> {
                List<UserDto> users = tuple.getT1();
                long total = tuple.getT2();

                PageResponse<UserDto> response = PageResponse.<UserDto>builder()
                    .content(users)
                    .page(page)
                    .size(size)
                    .totalElements(total)
                    .totalPages((int) Math.ceil((double) total / size))
                    .build();

                return ServerResponse.ok()
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(response);
            });
    }
}
```

### File Upload Handler

```java
@Component
@RequiredArgsConstructor
public class FileUploadHandler {

    private final FileStorageService storageService;
    private final long maxFileSize = 10 * 1024 * 1024; // 10MB

    public Mono<ServerResponse> uploadFile(ServerRequest request) {
        return request.multipartData()
            .flatMap(parts -> {
                Map<String, Part> partMap = parts.toSingleValueMap();
                Part filePart = partMap.get("file");

                if (filePart == null) {
                    return Mono.error(new BadRequestException("No file provided"));
                }

                if (!(filePart instanceof FilePart)) {
                    return Mono.error(new BadRequestException("Invalid file part"));
                }

                FilePart file = (FilePart) filePart;
                return validateAndStore(file);
            })
            .flatMap(fileInfo -> ServerResponse
                .created(URI.create("/api/files/" + fileInfo.getId()))
                .bodyValue(fileInfo));
    }

    private Mono<FileInfo> validateAndStore(FilePart file) {
        return DataBufferUtils.join(file.content())
            .flatMap(dataBuffer -> {
                long size = dataBuffer.readableByteCount();
                if (size > maxFileSize) {
                    DataBufferUtils.release(dataBuffer);
                    return Mono.error(new BadRequestException(
                        "File too large. Max size: " + maxFileSize));
                }

                String contentType = file.headers().getContentType() != null
                    ? file.headers().getContentType().toString()
                    : "application/octet-stream";

                return storageService.store(
                    file.filename(),
                    contentType,
                    dataBuffer.asInputStream()
                );
            });
    }

    public Mono<ServerResponse> downloadFile(ServerRequest request) {
        String fileId = request.pathVariable("id");

        return storageService.getFile(fileId)
            .flatMap(file -> ServerResponse.ok()
                .contentType(MediaType.parseMediaType(file.getContentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"" + file.getFilename() + "\"")
                .body(file.getContent(), DataBuffer.class))
            .switchIfEmpty(ServerResponse.notFound().build());
    }
}
```

## WebClient Advanced Patterns

### Connection Pool Configuration

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient webClient() {
        // Connection provider with pool configuration
        ConnectionProvider provider = ConnectionProvider.builder("custom-pool")
            .maxConnections(500)
            .maxIdleTime(Duration.ofSeconds(20))
            .maxLifeTime(Duration.ofSeconds(60))
            .pendingAcquireTimeout(Duration.ofSeconds(60))
            .pendingAcquireMaxCount(1000)
            .evictInBackground(Duration.ofSeconds(120))
            .metrics(true)
            .build();

        // HTTP client with connection provider
        HttpClient httpClient = HttpClient.create(provider)
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5000)
            .responseTimeout(Duration.ofSeconds(30))
            .doOnConnected(conn -> conn
                .addHandlerLast(new ReadTimeoutHandler(30))
                .addHandlerLast(new WriteTimeoutHandler(30)));

        return WebClient.builder()
            .clientConnector(new ReactorClientHttpConnector(httpClient))
            .codecs(configurer -> configurer
                .defaultCodecs()
                .maxInMemorySize(16 * 1024 * 1024))
            .build();
    }
}
```

### Request/Response Logging

```java
@Component
@Slf4j
public class LoggingWebClientCustomizer {

    public WebClient.Builder customize(WebClient.Builder builder) {
        return builder
            .filter(logRequest())
            .filter(logResponse());
    }

    private ExchangeFilterFunction logRequest() {
        return ExchangeFilterFunction.ofRequestProcessor(request -> {
            log.debug("Request: {} {} Headers: {}",
                request.method(),
                request.url(),
                request.headers().entrySet().stream()
                    .filter(e -> !e.getKey().equalsIgnoreCase("Authorization"))
                    .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue)));
            return Mono.just(request);
        });
    }

    private ExchangeFilterFunction logResponse() {
        return ExchangeFilterFunction.ofResponseProcessor(response -> {
            log.debug("Response: {} Headers: {}",
                response.statusCode(),
                response.headers().asHttpHeaders());
            return Mono.just(response);
        });
    }
}
```

### OAuth2 Token Management

```java
@Service
@RequiredArgsConstructor
public class OAuth2WebClient {

    private final WebClient webClient;
    private final OAuth2TokenService tokenService;

    public <T> Mono<T> get(String uri, Class<T> responseType) {
        return executeWithToken(client -> client.get()
            .uri(uri)
            .retrieve()
            .bodyToMono(responseType));
    }

    public <T, R> Mono<R> post(String uri, T body, Class<R> responseType) {
        return executeWithToken(client -> client.post()
            .uri(uri)
            .bodyValue(body)
            .retrieve()
            .bodyToMono(responseType));
    }

    private <T> Mono<T> executeWithToken(Function<WebClient, Mono<T>> requestFunction) {
        return tokenService.getAccessToken()
            .flatMap(token -> {
                WebClient authenticatedClient = webClient.mutate()
                    .defaultHeader(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                    .build();
                return requestFunction.apply(authenticatedClient);
            })
            .retryWhen(Retry.backoff(1, Duration.ofMillis(100))
                .filter(e -> e instanceof UnauthorizedException)
                .doBeforeRetry(signal -> tokenService.refreshToken()));
    }
}

@Service
public class OAuth2TokenService {

    private final WebClient tokenClient;
    private final OAuth2Properties properties;
    private final AtomicReference<TokenInfo> tokenCache = new AtomicReference<>();

    public Mono<String> getAccessToken() {
        TokenInfo cached = tokenCache.get();
        if (cached != null && !cached.isExpired()) {
            return Mono.just(cached.getAccessToken());
        }

        return fetchNewToken()
            .map(token -> {
                tokenCache.set(token);
                return token.getAccessToken();
            });
    }

    public void refreshToken() {
        tokenCache.set(null);
    }

    private Mono<TokenInfo> fetchNewToken() {
        return tokenClient.post()
            .uri(properties.getTokenUri())
            .contentType(MediaType.APPLICATION_FORM_URLENCODED)
            .body(BodyInserters
                .fromFormData("grant_type", "client_credentials")
                .with("client_id", properties.getClientId())
                .with("client_secret", properties.getClientSecret()))
            .retrieve()
            .bodyToMono(TokenResponse.class)
            .map(response -> TokenInfo.builder()
                .accessToken(response.getAccessToken())
                .expiresAt(Instant.now().plusSeconds(response.getExpiresIn() - 60))
                .build());
    }
}
```

### Parallel Requests

```java
@Service
public class AggregationService {

    private final WebClient webClient;

    public Mono<AggregatedResponse> fetchAll(String userId) {
        Mono<UserProfile> profileMono = webClient.get()
            .uri("/users/{id}/profile", userId)
            .retrieve()
            .bodyToMono(UserProfile.class)
            .timeout(Duration.ofSeconds(5));

        Mono<List<Order>> ordersMono = webClient.get()
            .uri("/users/{id}/orders", userId)
            .retrieve()
            .bodyToFlux(Order.class)
            .collectList()
            .timeout(Duration.ofSeconds(5));

        Mono<UserPreferences> preferencesMono = webClient.get()
            .uri("/users/{id}/preferences", userId)
            .retrieve()
            .bodyToMono(UserPreferences.class)
            .timeout(Duration.ofSeconds(5))
            .onErrorReturn(UserPreferences.defaults());

        return Mono.zip(profileMono, ordersMono, preferencesMono)
            .map(tuple -> AggregatedResponse.builder()
                .profile(tuple.getT1())
                .orders(tuple.getT2())
                .preferences(tuple.getT3())
                .build());
    }

    // With error isolation
    public Mono<AggregatedResponse> fetchAllResilient(String userId) {
        Mono<Optional<UserProfile>> profileMono = fetchProfile(userId)
            .map(Optional::of)
            .onErrorReturn(Optional.empty());

        Mono<List<Order>> ordersMono = fetchOrders(userId)
            .onErrorReturn(Collections.emptyList());

        return Mono.zip(profileMono, ordersMono)
            .map(tuple -> AggregatedResponse.builder()
                .profile(tuple.getT1().orElse(null))
                .orders(tuple.getT2())
                .build());
    }
}
```

## SSE và WebSocket Patterns

### Advanced SSE with Heartbeat and Reconnection

```java
@RestController
@RequiredArgsConstructor
public class SSEController {

    private final EventService eventService;

    @GetMapping(value = "/events/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<?>> eventStream(
            @RequestParam String userId,
            @RequestHeader(value = "Last-Event-ID", required = false) String lastEventId) {

        // Resume from last event if reconnecting
        Flux<Event> events = lastEventId != null
            ? eventService.getEventsAfter(userId, lastEventId)
            : eventService.getEvents(userId);

        Flux<ServerSentEvent<Event>> eventFlux = events
            .map(event -> ServerSentEvent.<Event>builder()
                .id(event.getId())
                .event(event.getType())
                .data(event)
                .build());

        // Heartbeat every 30 seconds
        Flux<ServerSentEvent<?>> heartbeat = Flux.interval(Duration.ofSeconds(30))
            .map(i -> ServerSentEvent.builder()
                .event("heartbeat")
                .comment("keep-alive")
                .build());

        return Flux.merge(eventFlux, heartbeat)
            .doOnCancel(() -> eventService.unsubscribe(userId))
            .doOnError(e -> log.error("SSE error for user {}", userId, e));
    }
}
```

### WebSocket with STOMP

```java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic", "/queue");
        config.setApplicationDestinationPrefixes("/app");
        config.setUserDestinationPrefix("/user");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws")
            .setAllowedOrigins("*")
            .withSockJS();
    }
}

@Controller
@RequiredArgsConstructor
public class ChatController {

    private final SimpMessagingTemplate messagingTemplate;
    private final ChatService chatService;

    @MessageMapping("/chat.send")
    public void sendMessage(ChatMessage message, Principal principal) {
        message.setSender(principal.getName());
        message.setTimestamp(Instant.now());

        chatService.saveMessage(message)
            .doOnSuccess(saved -> {
                if (message.isPrivate()) {
                    messagingTemplate.convertAndSendToUser(
                        message.getRecipient(),
                        "/queue/messages",
                        saved
                    );
                } else {
                    messagingTemplate.convertAndSend(
                        "/topic/chat." + message.getRoomId(),
                        saved
                    );
                }
            })
            .subscribe();
    }

    @MessageMapping("/chat.typing")
    public void handleTyping(TypingEvent event, Principal principal) {
        event.setUser(principal.getName());
        messagingTemplate.convertAndSend(
            "/topic/chat." + event.getRoomId() + ".typing",
            event
        );
    }
}
```

### Raw WebSocket with Binary Data

```java
@Component
public class BinaryWebSocketHandler implements WebSocketHandler {

    private final DataProcessor dataProcessor;

    @Override
    public Mono<Void> handle(WebSocketSession session) {
        Flux<WebSocketMessage> output = session.receive()
            .filter(msg -> msg.getType() == WebSocketMessage.Type.BINARY)
            .flatMap(msg -> processMessage(msg.getPayload()))
            .map(result -> session.binaryMessage(factory ->
                factory.wrap(result)));

        return session.send(output)
            .doOnError(e -> log.error("WebSocket error", e))
            .doFinally(signal -> log.info("WebSocket closed: {}", signal));
    }

    private Mono<byte[]> processMessage(DataBuffer buffer) {
        byte[] data = new byte[buffer.readableByteCount()];
        buffer.read(data);
        DataBufferUtils.release(buffer);

        return dataProcessor.process(data);
    }
}
```

## Request/Response Processing

### Custom Argument Resolver

```java
@Configuration
public class WebFluxConfig implements WebFluxConfigurer {

    @Override
    public void configureArgumentResolvers(ArgumentResolverConfigurer configurer) {
        configurer.addCustomResolver(new CurrentUserArgumentResolver());
        configurer.addCustomResolver(new PageableArgumentResolver());
    }
}

public class CurrentUserArgumentResolver implements HandlerMethodArgumentResolver {

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.hasParameterAnnotation(CurrentUser.class)
            && parameter.getParameterType().equals(User.class);
    }

    @Override
    public Mono<Object> resolveArgument(
            MethodParameter parameter,
            BindingContext bindingContext,
            ServerWebExchange exchange) {

        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(auth -> (User) auth.getPrincipal());
    }
}

@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
public @interface CurrentUser {
}

// Usage
@GetMapping("/me")
public Mono<UserDto> getCurrentUser(@CurrentUser User user) {
    return Mono.just(UserMapper.toDto(user));
}
```

### Custom Response Handling

```java
@RestControllerAdvice
public class ResponseWrapper implements ResponseBodyResultHandler {

    @Override
    public Mono<Void> handleResult(ServerWebExchange exchange, HandlerResult result) {
        Object body = result.getReturnValue();

        if (body instanceof Mono<?> mono) {
            return mono.flatMap(value -> writeResponse(exchange, wrap(value)));
        } else if (body instanceof Flux<?> flux) {
            return flux.collectList()
                .flatMap(list -> writeResponse(exchange, wrap(list)));
        }

        return writeResponse(exchange, wrap(body));
    }

    private ApiResponse<?> wrap(Object data) {
        return ApiResponse.builder()
            .success(true)
            .data(data)
            .timestamp(Instant.now())
            .build();
    }

    private Mono<Void> writeResponse(ServerWebExchange exchange, Object body) {
        ServerHttpResponse response = exchange.getResponse();
        response.getHeaders().setContentType(MediaType.APPLICATION_JSON);

        return response.writeWith(
            Mono.fromCallable(() -> {
                byte[] bytes = objectMapper.writeValueAsBytes(body);
                return response.bufferFactory().wrap(bytes);
            })
        );
    }
}
```

## Error Handling Strategies

### Comprehensive Error Handler

```java
@Component
@Order(-2)
@RequiredArgsConstructor
@Slf4j
public class GlobalErrorWebExceptionHandler extends AbstractErrorWebExceptionHandler {

    private final ObjectMapper objectMapper;

    public GlobalErrorWebExceptionHandler(
            ErrorAttributes errorAttributes,
            WebProperties.Resources resources,
            ApplicationContext applicationContext,
            ObjectMapper objectMapper) {
        super(errorAttributes, resources, applicationContext);
        this.objectMapper = objectMapper;
        setMessageReaders(List.of());
        setMessageWriters(List.of());
    }

    @Override
    protected RouterFunction<ServerResponse> getRoutingFunction(ErrorAttributes errorAttributes) {
        return RouterFunctions.route(RequestPredicates.all(), this::renderErrorResponse);
    }

    private Mono<ServerResponse> renderErrorResponse(ServerRequest request) {
        Throwable error = getError(request);
        ErrorInfo errorInfo = mapToErrorInfo(error, request);

        logError(error, errorInfo, request);

        return ServerResponse
            .status(errorInfo.getStatus())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(ErrorResponse.builder()
                .code(errorInfo.getCode())
                .message(errorInfo.getMessage())
                .details(errorInfo.getDetails())
                .path(request.path())
                .timestamp(Instant.now())
                .traceId(getTraceId(request))
                .build());
    }

    private ErrorInfo mapToErrorInfo(Throwable error, ServerRequest request) {
        return switch (error) {
            case ValidationException e -> new ErrorInfo(
                HttpStatus.BAD_REQUEST,
                "VALIDATION_ERROR",
                "Validation failed",
                e.getErrors()
            );
            case NotFoundException e -> new ErrorInfo(
                HttpStatus.NOT_FOUND,
                "NOT_FOUND",
                e.getMessage(),
                null
            );
            case UnauthorizedException e -> new ErrorInfo(
                HttpStatus.UNAUTHORIZED,
                "UNAUTHORIZED",
                "Authentication required",
                null
            );
            case ForbiddenException e -> new ErrorInfo(
                HttpStatus.FORBIDDEN,
                "FORBIDDEN",
                "Access denied",
                null
            );
            case ConflictException e -> new ErrorInfo(
                HttpStatus.CONFLICT,
                "CONFLICT",
                e.getMessage(),
                null
            );
            case RateLimitException e -> new ErrorInfo(
                HttpStatus.TOO_MANY_REQUESTS,
                "RATE_LIMITED",
                "Too many requests",
                Map.of("retryAfter", e.getRetryAfterSeconds())
            );
            case WebClientResponseException e -> new ErrorInfo(
                HttpStatus.BAD_GATEWAY,
                "UPSTREAM_ERROR",
                "External service error",
                null
            );
            default -> new ErrorInfo(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "INTERNAL_ERROR",
                "An unexpected error occurred",
                null
            );
        };
    }

    private void logError(Throwable error, ErrorInfo errorInfo, ServerRequest request) {
        if (errorInfo.getStatus().is5xxServerError()) {
            log.error("Server error on {} {}: {}",
                request.method(), request.path(), error.getMessage(), error);
        } else {
            log.warn("Client error on {} {}: {}",
                request.method(), request.path(), error.getMessage());
        }
    }

    private String getTraceId(ServerRequest request) {
        return request.headers().firstHeader("X-Trace-Id");
    }
}
```

## Filter Patterns

### Authentication Filter

```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
@RequiredArgsConstructor
public class JwtAuthenticationWebFilter implements WebFilter {

    private final JwtTokenProvider tokenProvider;
    private final ReactiveUserDetailsService userDetailsService;

    private static final List<String> PUBLIC_PATHS = List.of(
        "/api/auth/login",
        "/api/auth/register",
        "/api/public/**",
        "/actuator/health"
    );

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();
        String path = request.getPath().value();

        if (isPublicPath(path)) {
            return chain.filter(exchange);
        }

        return extractToken(request)
            .flatMap(token -> tokenProvider.validateToken(token)
                .filter(valid -> valid)
                .flatMap(valid -> tokenProvider.getUsername(token))
                .flatMap(userDetailsService::findByUsername)
                .map(this::createAuthentication))
            .flatMap(auth -> chain.filter(exchange)
                .contextWrite(ReactiveSecurityContextHolder.withAuthentication(auth)))
            .switchIfEmpty(chain.filter(exchange));
    }

    private boolean isPublicPath(String path) {
        return PUBLIC_PATHS.stream()
            .anyMatch(pattern -> new AntPathMatcher().match(pattern, path));
    }

    private Mono<String> extractToken(ServerHttpRequest request) {
        String bearerToken = request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        if (bearerToken != null && bearerToken.startsWith("Bearer ")) {
            return Mono.just(bearerToken.substring(7));
        }
        return Mono.empty();
    }

    private Authentication createAuthentication(UserDetails userDetails) {
        return new UsernamePasswordAuthenticationToken(
            userDetails,
            null,
            userDetails.getAuthorities()
        );
    }
}
```

### Rate Limiting Filter

```java
@Component
@RequiredArgsConstructor
public class RateLimitingWebFilter implements WebFilter {

    private final RateLimiterService rateLimiterService;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String clientId = getClientId(exchange);
        String endpoint = exchange.getRequest().getPath().value();

        return rateLimiterService.isAllowed(clientId, endpoint)
            .flatMap(allowed -> {
                if (allowed) {
                    return chain.filter(exchange);
                } else {
                    return rateLimiterService.getRetryAfter(clientId, endpoint)
                        .flatMap(retryAfter -> {
                            ServerHttpResponse response = exchange.getResponse();
                            response.setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                            response.getHeaders().add("Retry-After",
                                String.valueOf(retryAfter));
                            return response.setComplete();
                        });
                }
            });
    }

    private String getClientId(ServerWebExchange exchange) {
        // Try to get from authenticated user
        return exchange.getPrincipal()
            .map(Principal::getName)
            .defaultIfEmpty(getClientIp(exchange))
            .block();
    }

    private String getClientIp(ServerWebExchange exchange) {
        String xForwardedFor = exchange.getRequest().getHeaders()
            .getFirst("X-Forwarded-For");
        if (xForwardedFor != null) {
            return xForwardedFor.split(",")[0].trim();
        }
        InetSocketAddress remoteAddress = exchange.getRequest().getRemoteAddress();
        return remoteAddress != null ? remoteAddress.getHostString() : "unknown";
    }
}
```

### Request/Response Logging Filter

```java
@Component
@Slf4j
public class RequestLoggingWebFilter implements WebFilter {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        long startTime = System.currentTimeMillis();
        ServerHttpRequest request = exchange.getRequest();

        String requestId = UUID.randomUUID().toString();

        log.info("Request [{}] {} {} from {}",
            requestId,
            request.getMethod(),
            request.getPath(),
            getClientIp(request));

        ServerWebExchange mutatedExchange = exchange.mutate()
            .request(request.mutate()
                .header("X-Request-Id", requestId)
                .build())
            .build();

        return chain.filter(mutatedExchange)
            .doFinally(signalType -> {
                long duration = System.currentTimeMillis() - startTime;
                HttpStatusCode status = exchange.getResponse().getStatusCode();

                log.info("Response [{}] {} {} - {} in {}ms",
                    requestId,
                    request.getMethod(),
                    request.getPath(),
                    status != null ? status.value() : "unknown",
                    duration);
            });
    }
}
```

### Caching Filter

```java
@Component
@RequiredArgsConstructor
public class CachingWebFilter implements WebFilter {

    private final ReactiveRedisTemplate<String, CachedResponse> cacheTemplate;
    private final ObjectMapper objectMapper;

    private static final Duration DEFAULT_TTL = Duration.ofMinutes(5);

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();

        if (!HttpMethod.GET.equals(request.getMethod())) {
            return chain.filter(exchange);
        }

        String cacheKey = buildCacheKey(request);

        return cacheTemplate.opsForValue().get(cacheKey)
            .flatMap(cached -> writeCachedResponse(exchange, cached))
            .switchIfEmpty(Mono.defer(() ->
                cacheAndProceed(exchange, chain, cacheKey)));
    }

    private Mono<Void> writeCachedResponse(
            ServerWebExchange exchange,
            CachedResponse cached) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatusCode.valueOf(cached.getStatusCode()));
        response.getHeaders().putAll(cached.getHeaders());
        response.getHeaders().add("X-Cache", "HIT");

        return response.writeWith(
            Mono.just(response.bufferFactory().wrap(cached.getBody()))
        );
    }

    private Mono<Void> cacheAndProceed(
            ServerWebExchange exchange,
            WebFilterChain chain,
            String cacheKey) {

        ServerHttpResponseDecorator decoratedResponse =
            new ServerHttpResponseDecorator(exchange.getResponse()) {

            @Override
            public Mono<Void> writeWith(Publisher<? extends DataBuffer> body) {
                return DataBufferUtils.join(body)
                    .flatMap(buffer -> {
                        byte[] bytes = new byte[buffer.readableByteCount()];
                        buffer.read(bytes);
                        DataBufferUtils.release(buffer);

                        CachedResponse cached = new CachedResponse(
                            getStatusCode().value(),
                            getHeaders(),
                            bytes
                        );

                        return cacheTemplate.opsForValue()
                            .set(cacheKey, cached, DEFAULT_TTL)
                            .then(getDelegate().writeWith(
                                Mono.just(bufferFactory().wrap(bytes))));
                    });
            }
        };

        decoratedResponse.getHeaders().add("X-Cache", "MISS");

        return chain.filter(exchange.mutate()
            .response(decoratedResponse)
            .build());
    }

    private String buildCacheKey(ServerHttpRequest request) {
        return "cache:" + request.getPath().value() +
            "?" + request.getQueryParams().toString();
    }
}
```
