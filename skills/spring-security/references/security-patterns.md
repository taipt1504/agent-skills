# Security Patterns Reference

Full code examples for Spring Security: MVC and WebFlux configs, JWT, method security, CORS, file validation, rate limiting, logging, headers, testing, OWASP scanning.

## Table of Contents
- [JWT Authentication Filter (MVC)](#jwt-authentication-filter-mvc)
- [SecurityFilterChain (MVC)](#securityfilterchain-mvc)
- [SecurityWebFilterChain (WebFlux)](#securitywebfilterchain-webflux)
- [Method Security](#method-security)
- [CORS Configuration](#cors-configuration)
- [File Upload Validation](#file-upload-validation)
- [Path Traversal Prevention](#path-traversal-prevention)
- [JWT Token Provider](#jwt-token-provider)
- [Rate Limiting (Caffeine)](#rate-limiting-caffeine)
- [Rate Limiting (Resilience4j)](#rate-limiting-resilience4j)
- [Sensitive Data Logging](#sensitive-data-logging)
- [Security Headers Filter](#security-headers-filter)
- [Security Testing (MockMvc)](#security-testing-mockmvc)
- [Security Testing (WebTestClient)](#security-testing-webtestclient)
- [OWASP Dependency Scanning](#owasp-dependency-scanning)

---

## JWT Authentication Filter (MVC)

```java
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider tokenProvider;
    private final UserDetailsService userDetailsService;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
            HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        String token = extractToken(request);
        if (token != null && tokenProvider.validateToken(token)) {
            String username = tokenProvider.getUsername(token);
            UserDetails userDetails = userDetailsService.loadUserByUsername(username);

            var authentication = new UsernamePasswordAuthenticationToken(
                userDetails, null, userDetails.getAuthorities());
            authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));

            SecurityContextHolder.getContext().setAuthentication(authentication);
        }

        filterChain.doFilter(request, response);
    }

    private String extractToken(HttpServletRequest request) {
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header != null && header.startsWith("Bearer ")) {
            return header.substring(7);
        }
        return null;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getServletPath();
        return path.startsWith("/api/v1/auth/") || path.startsWith("/actuator/health");
    }
}
```

---

## SecurityFilterChain (MVC)

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtFilter;
    private final AuthenticationEntryPoint authEntryPoint;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable) // Disable for stateless API
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .exceptionHandling(ex ->
                ex.authenticationEntryPoint(authEntryPoint))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/auth/**").permitAll()
                .requestMatchers("/actuator/health").permitAll()
                .requestMatchers("/api/v1/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated()
            )
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
            .build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12); // Cost factor 12
    }
}
```

---

## SecurityWebFilterChain (WebFlux)

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

### MVC (Blocking)

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    @PreAuthorize("@orderSecurity.isOwner(#id, authentication) or hasRole('ADMIN')")
    public OrderDto findById(Long id) { ... }

    @PreAuthorize("isAuthenticated()")
    public OrderDto createOrder(CreateOrderCommand command) { ... }

    @PostFilter("filterObject.ownerId == authentication.name or hasRole('ADMIN')")
    public List<OrderDto> findAll() { ... }
}

@Component("orderSecurity")
@RequiredArgsConstructor
public class OrderSecurityEvaluator {
    private final OrderRepository orderRepository;

    public boolean isOwner(Long orderId, Authentication auth) {
        return orderRepository.findById(orderId)
            .map(order -> order.getCustomerId().equals(auth.getName()))
            .orElse(false);
    }
}
```

### WebFlux (Reactive)

```java
@Service @RequiredArgsConstructor
@Slf4j
public class OrderService {

    @PreAuthorize("hasRole('ADMIN') or #userId == authentication.name")
    public Flux<Order> findByUser(String userId) { ... }

    @PreAuthorize("hasRole('ADMIN')")
    public Mono<Void> deleteOrder(String orderId) { ... }

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

## CORS Configuration

### MVC

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOrigins(List.of(
        "https://app.example.com",
        "https://admin.example.com"
    )); // NEVER use "*" in production
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH"));
    config.setAllowedHeaders(List.of("Authorization", "Content-Type"));
    config.setExposedHeaders(List.of("X-Request-Id"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L); // 1 hour preflight cache

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
}
```

### Anti-Pattern

```java
// BAD: Wildcard CORS -- allows any origin
config.setAllowedOrigins(List.of("*"));
config.addAllowedOriginPattern("*");     // Same problem
```

---

## File Upload Validation

```java
@Component
public class FileValidator {
    private static final Set<String> ALLOWED_EXTENSIONS = Set.of("jpg","jpeg","png","pdf","docx");
    private static final long MAX_SIZE = 5 * 1024 * 1024L;  // 5MB

    // Validate by magic bytes -- extensions can be spoofed
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

---

## Path Traversal Prevention

```java
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

            if (claims.getExpiration().before(new Date())) {
                throw new JwtValidationException("Token expired");
            }

            @SuppressWarnings("unchecked")
            List<String> roles = (List<String>) claims.get("roles");
            return new JwtClaims(claims.getSubject(), roles);
        } catch (JwtException e) {
            throw new JwtValidationException("Invalid token");
        }
    }
}
```

---

## Secrets & Configuration

```java
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
# application.yml -- reference env vars, never hardcode values
app:
  security:
    jwt-secret: ${JWT_SECRET}
    jwt-expiration: ${JWT_EXPIRATION:1h}
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
@ConfigurationProperties(prefix = "app.jwt")
@Validated
public record JwtProperties(
    @NotBlank String secret,
    @Positive long expirationMs,
    @NotBlank String issuer
) {}
```

```yaml
# application.yml
app:
  jwt:
    secret: ${JWT_SECRET}
    expiration-ms: ${JWT_EXPIRATION:3600000}
    issuer: ${JWT_ISSUER:my-app}
```

### .gitignore Rules

```
# Secrets
.env
*.pem
*.key
application-local.yml
application-secret.yml
```

---

## Rate Limiting (Caffeine)

Per-user rate limiting with Caffeine cache and Guava RateLimiter.

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

---

## Rate Limiting (Resilience4j)

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
// Mask PII in logs -- custom toString or @JsonIgnore
public record UserProfile(String id, String email, @JsonIgnore String passwordHash,
                          @JsonIgnore String creditCardNumber) {
    @Override
    public String toString() {
        return "UserProfile{id='%s', email='%s'}".formatted(id, maskEmail(email));
    }

    private static String maskEmail(String email) {
        if (email == null || !email.contains("@")) return "***";
        int atIdx = email.indexOf('@');
        return email.charAt(0) + "***" + email.substring(atIdx);
    }
}

// MDC for correlation -- no sensitive data
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
                // Never log: Authorization header, request body with passwords, tokens
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
        // HSTS -- only over HTTPS
        headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload");
    }
}
```

---

## Security Testing (MockMvc)

For MVC-based applications using `MockMvc`.

```java
@WebMvcTest(OrderController.class)
@Import(SecurityConfig.class)
class OrderControllerSecurityTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private OrderService orderService;

    @Test
    void shouldReturn401WhenNoToken() throws Exception {
        mockMvc.perform(get("/api/v1/orders"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser(roles = "USER")
    void shouldReturn403WhenInsufficientRole() throws Exception {
        mockMvc.perform(get("/api/v1/admin/users"))
            .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser(roles = "ADMIN")
    void shouldReturn200WithAdminRole() throws Exception {
        mockMvc.perform(get("/api/v1/admin/users"))
            .andExpect(status().isOk());
    }

    @Test
    void shouldRejectSqlInjectionAttempt() throws Exception {
        mockMvc.perform(get("/api/v1/users")
                .param("name", "'; DROP TABLE users; --")
                .with(user("testuser").roles("USER")))
            .andExpect(status().isBadRequest());
    }
}
```

---

## Security Testing (WebTestClient)

For WebFlux-based applications.

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
            .expectStatus().isBadRequest();
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

---

## OWASP Dependency Scanning

### Gradle Configuration

```groovy
// build.gradle
plugins {
    id 'org.owasp.dependencycheck' version '9.0.0'
}

dependencyCheck {
    failBuildOnCVSS = 7      // Block on HIGH/CRITICAL
    formats = ['HTML', 'JSON']
    suppressionFile = 'owasp-suppressions.xml'
}
```

Run: `./gradlew dependencyCheckAnalyze`

### CI/CD Integration

- Enable Dependabot or Renovate for automated dependency updates
- Run OWASP scan in CI pipeline, fail build on CVSS >= 7
- Review and update `owasp-suppressions.xml` for false positives
