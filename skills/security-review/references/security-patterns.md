# Security Patterns Reference

Full code examples: secrets config, file validation, JWT provider, method security, rate limiting, sensitive data logging, security headers, security testing.

## Table of Contents
- [Secrets & Configuration](#secrets--configuration)
- [File Upload Validation & Path Traversal](#file-upload-validation--path-traversal)
- [JWT Token Provider](#jwt-token-provider)
- [Spring Security WebFlux (Full Config)](#spring-security-webflux-full-config)
- [Method Security](#method-security)
- [Rate Limiting](#rate-limiting)
- [Sensitive Data Logging](#sensitive-data-logging)
- [Security Headers Filter](#security-headers-filter)
- [Security Testing with WebTestClient](#security-testing-with-webtestclient)

---

## Secrets & Configuration

```java
// ✅ Application properties mapping
@Configuration
@ConfigurationProperties(prefix = "app.security")
@Validated
public class SecurityProperties {
    @NotBlank private String jwtSecret;
    @NotNull  private Duration jwtExpiration;
    @NotBlank private String encryptionKey;
    // getters/setters
}
```

```yaml
# application.yml — reference env vars, never hardcode values
app:
  security:
    jwt-secret: ${JWT_SECRET}               # from environment
    jwt-expiration: ${JWT_EXPIRATION:1h}    # with fallback
    encryption-key: ${ENCRYPTION_KEY}

# For Vault (Spring Cloud Vault)
spring:
  cloud:
    vault:
      host: vault.example.com
      authentication: KUBERNETES
      kv:
        enabled: true
        default-context: order-service
```

```java
// ❌ Never
private static final String API_KEY = "sk-proj-xxxx-hardcoded";

// ✅ Always
@Value("${app.api-key}")
private String apiKey;
```

---

## File Upload Validation & Path Traversal

```java
@Component
public class FileValidator {
    private static final Set<String> ALLOWED_EXTENSIONS = Set.of("jpg","jpeg","png","pdf","docx");
    private static final long MAX_SIZE = 5 * 1024 * 1024L;  // 5MB

    // Validate by magic bytes — extensions can be spoofed
    private static final Map<byte[], String> MAGIC_BYTES = Map.of(
        new byte[]{(byte)0xFF, (byte)0xD8, (byte)0xFF}, "image/jpeg",
        new byte[]{(byte)0x89, 0x50, 0x4E, 0x47}, "image/png",
        new byte[]{0x25, 0x50, 0x44, 0x46}, "application/pdf"
    );

    public Mono<Void> validate(FilePart file) {
        String filename = StringUtils.cleanPath(file.filename());
        if (filename.contains("..") || filename.contains("/")) {
            return Mono.error(new BadRequestException("Invalid filename"));
        }
        String ext = getExtension(filename).toLowerCase();
        if (!ALLOWED_EXTENSIONS.contains(ext)) {
            return Mono.error(new BadRequestException("File type not allowed: " + ext));
        }
        long size = file.headers().getContentLength();
        if (size > MAX_SIZE) {
            return Mono.error(new BadRequestException("File too large"));
        }
        return Mono.empty();
    }
}
```

```java
// Path traversal prevention — always use this before reading/writing files
@Service
public class SecureFileService {
    private final Path uploadRoot;

    public Mono<Path> resolveSecurely(String filename) {
        Path resolved = uploadRoot.resolve(StringUtils.cleanPath(filename)).normalize();
        if (!resolved.startsWith(uploadRoot)) {
            return Mono.error(new SecurityException("Path traversal detected"));
        }
        return Mono.just(resolved);
    }
}
```

---

## JWT Token Provider

```java
@Component
public class JwtTokenProvider {

    private final SecretKey secretKey;
    private final Duration expiration;

    public JwtTokenProvider(SecurityProperties props) {
        // ✅ Use hmacShaKeyFor — safe key derivation
        this.secretKey = Keys.hmacShaKeyFor(props.getJwtSecret().getBytes(StandardCharsets.UTF_8));
        this.expiration = props.getJwtExpiration();
    }

    public String generate(String userId, List<String> roles) {
        Instant now = Instant.now();
        return Jwts.builder()
            .subject(userId)
            .claim("roles", roles)
            .issuedAt(Date.from(now))
            .expiration(Date.from(now.plus(expiration)))
            .signWith(secretKey)
            .compact();
    }

    public JwtClaims validate(String token) {
        try {
            var claims = Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();

            // ✅ Verify expiry (parser does this automatically but be explicit)
            if (claims.getExpiration().before(new Date())) {
                throw new JwtValidationException("Token expired");
            }

            @SuppressWarnings("unchecked")
            List<String> roles = (List<String>) claims.get("roles");
            return new JwtClaims(claims.getSubject(), roles);
        } catch (JwtException e) {
            // ✅ Generic message — don't expose JWT internals
            throw new JwtValidationException("Invalid token");
        }
    }
}
```

---

## Spring Security WebFlux (Full Config)

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtTokenProvider tokenProvider;

    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(csrf -> csrf.disable())  // API-only: no forms/sessions
            .cors(cors -> cors.configurationSource(corsConfigSource()))
            .headers(headers -> headers
                .frameOptions(ServerHttpSecurity.HeaderSpec.FrameOptionsSpec::deny)
                .contentTypeOptions(Customizer.withDefaults())
                .hsts(hsts -> hsts.maxAge(Duration.ofDays(365)).includeSubdomains(true)))
            .authorizeExchange(auth -> auth
                .pathMatchers("/api/public/**").permitAll()
                .pathMatchers("/actuator/health", "/actuator/info").permitAll()
                .pathMatchers("/api/admin/**").hasRole("ADMIN")
                .pathMatchers(HttpMethod.GET, "/api/v1/**").hasAnyRole("USER", "ADMIN")
                .anyExchange().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt ->
                jwt.jwtAuthenticationConverter(jwtConverter())))
            .build();
    }

    @Bean
    public CorsConfigurationSource corsConfigSource() {
        var config = new CorsConfiguration();
        // ✅ Explicit origins — no wildcard in production
        config.setAllowedOrigins(List.of("https://app.example.com"));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key"));
        config.setMaxAge(3600L);
        var source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", config);
        return source;
    }

    @Bean
    public ReactiveJwtAuthenticationConverter jwtConverter() {
        var converter = new ReactiveJwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            @SuppressWarnings("unchecked")
            List<String> roles = (List<String>) jwt.getClaims().getOrDefault("roles", List.of());
            return Flux.fromIterable(roles)
                .map(role -> (GrantedAuthority) new SimpleGrantedAuthority("ROLE_" + role));
        });
        return converter;
    }
}
```

---

## Method Security

```java
@Service @RequiredArgsConstructor
@Slf4j
public class OrderService {

    // ✅ Method-level authorization with SpEL
    @PreAuthorize("hasRole('ADMIN') or #userId == authentication.name")
    public Flux<Order> findByUser(String userId) { ... }

    @PreAuthorize("hasRole('ADMIN')")
    public Mono<Void> deleteOrder(String orderId) { ... }

    // ✅ Custom PermissionEvaluator
    @PreAuthorize("@orderPermissions.canModify(authentication, #orderId)")
    public Mono<Order> updateOrder(String orderId, UpdateOrderRequest request) { ... }
}

@Component
public class OrderPermissions {
    public Mono<Boolean> canModify(Authentication auth, String orderId) {
        if (auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"))) {
            return Mono.just(true);
        }
        return orderRepository.findById(orderId)
            .map(order -> order.getCustomerId().equals(auth.getName()))
            .defaultIfEmpty(false);
    }
}
```

---

## Rate Limiting

### Per-User Rate Limiting with Caffeine

```java
@Configuration
public class RateLimitConfig {
    @Bean
    public Cache<String, RateLimiter> rateLimiterCache() {
        return Caffeine.newBuilder()
            .maximumSize(10_000)
            .expireAfterAccess(Duration.ofMinutes(10))
            .build();
    }
}

@Component @RequiredArgsConstructor
public class RateLimitFilter implements WebFilter {
    private final Cache<String, RateLimiter> cache;

    @Override
    public Mono<WebFilterChain> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String key = resolveKey(exchange);
        RateLimiter limiter = cache.get(key, k ->
            RateLimiter.create(100.0 / 60));  // 100 req/min

        if (!limiter.tryAcquire()) {
            exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            exchange.getResponse().getHeaders().set("Retry-After", "60");
            return exchange.getResponse().setComplete().then(Mono.empty());
        }
        return chain.filter(exchange).then(Mono.empty());
    }

    private String resolveKey(ServerWebExchange exchange) {
        // Per-user if authenticated, else per-IP
        return Optional.ofNullable(exchange.getRequest().getHeaders().getFirst("X-User-Id"))
            .orElseGet(() -> exchange.getRequest().getRemoteAddress().getAddress().getHostAddress());
    }
}
```

### Resilience4j Rate Limiter

```yaml
resilience4j:
  ratelimiter:
    instances:
      payment-api:
        limit-for-period: 10
        limit-refresh-period: 1s
        timeout-duration: 0ms  # fail fast
      default:
        limit-for-period: 100
        limit-refresh-period: 1m
        timeout-duration: 25ms
```

```java
@RateLimiter(name = "payment-api", fallbackMethod = "rateLimitFallback")
public Mono<PaymentResult> processPayment(PaymentRequest request) { ... }

public Mono<PaymentResult> rateLimitFallback(PaymentRequest req, RequestNotPermitted ex) {
    return Mono.error(new TooManyRequestsException("Rate limit exceeded, retry later"));
}
```

---

## Sensitive Data Logging

```java
// ✅ Mask PII in logs — custom toString or @JsonIgnore
public record UserProfile(String id, String email, @JsonIgnore String passwordHash,
                          @JsonIgnore String creditCardNumber) {
    @Override
    public String toString() {
        // Mask sensitive fields in logs
        return "UserProfile{id='%s', email='%s'}".formatted(id, maskEmail(email));
    }

    private static String maskEmail(String email) {
        if (email == null || !email.contains("@")) return "***";
        int atIdx = email.indexOf('@');
        return email.charAt(0) + "***" + email.substring(atIdx);
    }
}

// ✅ MDC for correlation — no sensitive data
@Component @Slf4j
public class RequestLoggingFilter implements WebFilter {
    @Override
    public Mono<WebFilterChain> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String traceId = UUID.randomUUID().toString().substring(0, 8);
        return chain.filter(exchange)
            .contextWrite(Context.of("traceId", traceId))
            .doOnSubscribe(s -> {
                log.info("Request: {} {} traceId={}",
                    exchange.getRequest().getMethod(),
                    exchange.getRequest().getPath(),
                    traceId);
                // ✅ Never log: Authorization header, request body with passwords, tokens
            });
    }
}
```

---

## Security Headers Filter

```java
@Component
public class SecurityHeadersFilter implements WebFilter {

    @Override
    public Mono<WebFilterChain> filter(ServerWebExchange exchange, WebFilterChain chain) {
        return chain.filter(exchange)
            .doOnSuccess(v -> addSecurityHeaders(exchange.getResponse()));
    }

    private void addSecurityHeaders(ServerHttpResponse response) {
        HttpHeaders headers = response.getHeaders();
        headers.set("X-Content-Type-Options", "nosniff");
        headers.set("X-Frame-Options", "DENY");
        headers.set("X-XSS-Protection", "1; mode=block");
        headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
        headers.set("Permissions-Policy", "geolocation=(), microphone=(), camera=()");
        headers.set("Content-Security-Policy",
            "default-src 'self'; " +
            "script-src 'self'; " +
            "style-src 'self'; " +
            "img-src 'self' data: https:; " +
            "frame-ancestors 'none'");
        // HSTS — only over HTTPS
        headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload");
    }
}
```

---

## Security Testing with WebTestClient

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SecurityIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void shouldReturn401WhenNoToken() {
        webTestClient.get().uri("/api/v1/orders")
            .exchange()
            .expectStatus().isUnauthorized();
    }

    @Test
    void shouldReturn403WhenInsufficientRole() {
        webTestClient.get().uri("/api/v1/admin/users")
            .headers(h -> h.setBearerAuth(tokenForRole("USER")))
            .exchange()
            .expectStatus().isForbidden();
    }

    @Test
    void shouldReturn200WithValidAdminToken() {
        webTestClient.get().uri("/api/v1/admin/users")
            .headers(h -> h.setBearerAuth(tokenForRole("ADMIN")))
            .exchange()
            .expectStatus().isOk();
    }

    @Test
    void shouldRejectSqlInjectionAttempt() {
        webTestClient.get()
            .uri(u -> u.path("/api/v1/users").queryParam("name", "'; DROP TABLE users; --").build())
            .headers(h -> h.setBearerAuth(userToken()))
            .exchange()
            .expectStatus().isBadRequest();  // validator rejects malicious input
    }

    @Test
    void shouldIncludeSecurityHeaders() {
        webTestClient.get().uri("/api/v1/public/health")
            .exchange()
            .expectHeader().valueEquals("X-Content-Type-Options", "nosniff")
            .expectHeader().valueEquals("X-Frame-Options", "DENY");
    }

    @Test
    void shouldNotExposeInternalErrorDetails() {
        webTestClient.get().uri("/api/v1/orders/trigger-error")
            .headers(h -> h.setBearerAuth(userToken()))
            .exchange()
            .expectStatus().is5xxServerError()
            .expectBody()
            .jsonPath("$.detail").isEqualTo("An unexpected error occurred")
            .jsonPath("$.stackTrace").doesNotExist();
    }

    private String tokenForRole(String role) {
        return jwtProvider.generate("test-user", List.of(role));
    }
}
```
