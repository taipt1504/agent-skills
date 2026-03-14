# WebClient, SSE & Security Reference

WebClient configuration, SSE streaming, and reactive Spring Security.

## Table of Contents
- [WebClient Configuration](#webclient-configuration)
- [WebClient Usage Patterns](#webclient-usage-patterns)
- [SSE with Sinks](#sse-with-sinks)
- [Reactive Spring Security](#reactive-spring-security)
- [JWT Authentication](#jwt-authentication)
- [Method Security](#method-security)

---

## WebClient Configuration

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient paymentWebClient() {
        // Connection pool — shared across requests
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

## WebClient Usage Patterns

```java
@Service @RequiredArgsConstructor
public class PaymentClient {
    private final WebClient paymentWebClient;

    // Simple GET
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

    // Exchange (full response access)
    public Mono<ResponseEntity<byte[]>> downloadReport(String reportId) {
        return paymentWebClient.get()
            .uri("/reports/{id}", reportId)
            .retrieve()
            .toEntity(byte[].class);
    }
}
```

---

## SSE with Sinks

Use `Sinks` to push events to multiple SSE subscribers.

```java
@Service
public class NotificationService {
    // Many-unicast: multiple consumers, each gets their own message copy
    private final Sinks.Many<Notification> sink = Sinks.many().multicast()
        .onBackpressureBuffer(1000, false);  // false = don't auto-cancel

    public void publish(Notification notification) {
        sink.tryEmitNext(notification);  // non-blocking push
    }

    public Flux<Notification> subscribe() {
        return sink.asFlux()
            .onBackpressureDrop(n -> log.warn("Dropped notification: {}", n.id()));
    }

    // Per-user notifications using subjects map
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

// SSE controller
@RestController @RequiredArgsConstructor
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
                .comment("keep-alive")
                .build())
            .mergeWith(heartbeat());  // prevent proxy timeouts
    }

    // Keep-alive heartbeat
    private Flux<ServerSentEvent<Notification>> heartbeat() {
        return Flux.interval(Duration.ofSeconds(30))
            .map(tick -> ServerSentEvent.<Notification>builder()
                .comment("heartbeat")
                .build());
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
            .csrf(ServerHttpSecurity.CsrfSpec::disable)  // for API-only services
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

    @Bean
    public ReactiveJwtDecoder jwtDecoder(@Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri}") String issuerUri) {
        return ReactiveJwtDecoders.fromIssuerLocation(issuerUri);
    }
}
```

---

## JWT Authentication

```java
// Custom JWT filter (when not using oauth2ResourceServer)
@Component @RequiredArgsConstructor
public class JwtAuthenticationWebFilter implements WebFilter {
    private final JwtTokenValidator tokenValidator;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        return Mono.justOrEmpty(exchange.getRequest().getHeaders().getFirst(HttpHeaders.AUTHORIZATION))
            .filter(header -> header.startsWith("Bearer "))
            .map(header -> header.substring(7))
            .flatMap(tokenValidator::validate)
            .flatMap(auth -> chain.filter(exchange)
                .contextWrite(ReactiveSecurityContextHolder.withAuthentication(auth)))
            .switchIfEmpty(chain.filter(exchange));
    }
}

// Accessing authenticated user
@GetMapping("/api/profile")
public Mono<UserProfile> getProfile() {
    return ReactiveSecurityContextHolder.getContext()
        .map(SecurityContext::getAuthentication)
        .map(auth -> (Jwt) auth.getPrincipal())
        .flatMap(jwt -> userService.findBySubject(jwt.getSubject()));
}

// Propagating security context downstream (WebClient)
public Mono<Object> callDownstream() {
    return ReactiveSecurityContextHolder.getContext()
        .map(ctx -> (Jwt) ctx.getAuthentication().getPrincipal())
        .map(jwt -> jwt.getTokenValue())
        .flatMap(token -> webClient.get()
            .uri("/downstream")
            .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
            .retrieve()
            .bodyToMono(Object.class));
}
```

---

## Method Security

```java
@EnableReactiveMethodSecurity  // on @Configuration class

// Usage on service methods
@PreAuthorize("hasRole('ADMIN')")
public Mono<List<UserResponse>> getAllUsers() { ... }

@PreAuthorize("hasRole('USER') and #userId == authentication.principal.subject")
public Mono<UserResponse> getUser(String userId) { ... }

@PostAuthorize("returnObject.map(u -> u.ownerId() == authentication.principal.subject)")
public Mono<Resource> getResource(Long resourceId) { ... }

// Custom permission evaluator
@PreAuthorize("@orderPermissionEvaluator.canAccess(authentication, #orderId)")
public Mono<Order> getOrder(Long orderId) { ... }

@Component
public class OrderPermissionEvaluator {
    private final OrderRepository orderRepository;

    public Mono<Boolean> canAccess(Authentication auth, Long orderId) {
        String userId = ((Jwt) auth.getPrincipal()).getSubject();
        return orderRepository.findById(orderId)
            .map(order -> order.customerId().equals(userId));
    }
}
```
