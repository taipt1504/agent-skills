---
name: security-review
description: Use this skill when adding authentication, handling user input, working with secrets, creating API endpoints, or implementing payment/sensitive features. Provides comprehensive security checklist and patterns for Java Spring applications.
---

# Security Review Skill

This skill ensures all Java Spring code follows security best practices and identifies potential vulnerabilities.

## When to Activate

- Implementing authentication or authorization
- Handling user input or file uploads
- Creating new API endpoints
- Working with secrets or credentials
- Implementing payment features
- Storing or transmitting sensitive data
- Integrating third-party APIs
- Database operations with user-provided data

## Security Checklist

### 1. Secrets Management

#### NEVER Do This

```java
// Hardcoded secrets - CRITICAL VULNERABILITY
private static final String API_KEY = "sk-proj-xxxxx";
private static final String DB_PASSWORD = "password123";

// Secrets in properties file committed to git
// application.properties
// spring.datasource.password=mySecretPassword
```

#### ALWAYS Do This

```java
@Configuration
@ConfigurationProperties(prefix = "app.secrets")
@Validated
public class SecretsConfig {

    @NotBlank(message = "API key is required")
    private String apiKey;

    @NotBlank(message = "Database password is required")
    private String databasePassword;

    // getters and setters
}

// Or using @Value
@Service
public class ExternalApiClient {

    private final String apiKey;

    public ExternalApiClient(@Value("${app.secrets.api-key}") String apiKey) {
        if (apiKey == null || apiKey.isBlank()) {
            throw new IllegalStateException("API key not configured");
        }
        this.apiKey = apiKey;
    }
}
```

#### Verification Steps

- [ ] No hardcoded API keys, tokens, or passwords
- [ ] All secrets in environment variables or external config
- [ ] `application-local.yml` in .gitignore
- [ ] No secrets in git history
- [ ] Production secrets in Vault/AWS Secrets Manager/K8s Secrets
- [ ] Secrets rotation policy in place

### 2. Input Validation

#### Always Validate User Input

```java
public record CreateUserRequest(
    @NotBlank(message = "Email is required")
    @Email(message = "Invalid email format")
    String email,

    @NotBlank(message = "Name is required")
    @Size(min = 1, max = 100, message = "Name must be 1-100 characters")
    @Pattern(regexp = "^[a-zA-Z\\s]+$", message = "Name can only contain letters and spaces")
    String name,

    @NotNull(message = "Age is required")
    @Min(value = 0, message = "Age must be positive")
    @Max(value = 150, message = "Age must be realistic")
    Integer age
) {}

@RestController
@Validated
public class UserController {

    @PostMapping("/api/users")
    public Mono<ResponseEntity<User>> createUser(@Valid @RequestBody CreateUserRequest request) {
        return userService.create(request)
            .map(user -> ResponseEntity.status(HttpStatus.CREATED).body(user));
    }
}
```

#### File Upload Validation

```java
@Service
public class FileUploadService {

    private static final long MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB
    private static final Set<String> ALLOWED_TYPES = Set.of(
        "image/jpeg", "image/png", "image/gif"
    );
    private static final Set<String> ALLOWED_EXTENSIONS = Set.of(
        ".jpg", ".jpeg", ".png", ".gif"
    );

    public Mono<FileUploadResult> uploadFile(FilePart filePart) {
        return validateFile(filePart)
            .flatMap(this::saveFile);
    }

    private Mono<FilePart> validateFile(FilePart filePart) {
        String filename = filePart.filename().toLowerCase();
        
        // Validate extension
        String extension = filename.substring(filename.lastIndexOf('.'));
        if (!ALLOWED_EXTENSIONS.contains(extension)) {
            return Mono.error(new InvalidFileException("Invalid file extension"));
        }

        // Validate content type
        MediaType contentType = filePart.headers().getContentType();
        if (contentType == null || !ALLOWED_TYPES.contains(contentType.toString())) {
            return Mono.error(new InvalidFileException("Invalid content type"));
        }

        // Validate size
        return filePart.content()
            .reduce(0L, (size, buffer) -> size + buffer.readableByteCount())
            .flatMap(size -> {
                if (size > MAX_FILE_SIZE) {
                    return Mono.error(new InvalidFileException("File too large (max 5MB)"));
                }
                return Mono.just(filePart);
            });
    }
}
```

#### Path Traversal Prevention

```java
@Service
public class FileService {

    private final Path uploadDir;

    public FileService(@Value("${app.upload.dir}") String uploadDir) {
        this.uploadDir = Path.of(uploadDir).toAbsolutePath().normalize();
    }

    public Mono<byte[]> readFile(String filename) {
        // Prevent path traversal
        Path filePath = uploadDir.resolve(filename).normalize();
        
        if (!filePath.startsWith(uploadDir)) {
            return Mono.error(new SecurityException("Invalid file path"));
        }

        // Safe to read
        return Mono.fromCallable(() -> Files.readAllBytes(filePath))
            .subscribeOn(Schedulers.boundedElastic());
    }
}
```

#### Verification Steps

- [ ] All user inputs validated with Bean Validation
- [ ] File uploads restricted (size, type, extension)
- [ ] Path traversal attacks prevented
- [ ] Whitelist validation (not blacklist)
- [ ] Error messages don't leak sensitive info
- [ ] Request rate limiting in place

### 3. SQL Injection Prevention

#### NEVER Concatenate SQL

```java
// DANGEROUS - SQL Injection vulnerability
String query = "SELECT * FROM users WHERE email = '" + userEmail + "'";
connection.prepareStatement(query).executeQuery();

// Also dangerous with R2DBC
String sql = "SELECT * FROM markets WHERE name LIKE '%" + searchTerm + "%'";
databaseClient.sql(sql).fetch().all();
```

#### ALWAYS Use Parameterized Queries

```java
// Safe - R2DBC parameterized query
@Repository
public class MarketRepositoryImpl implements MarketRepositoryCustom {

    private final DatabaseClient databaseClient;

    public Flux<Market> searchByName(String searchTerm) {
        return databaseClient.sql("""
            SELECT * FROM markets 
            WHERE name ILIKE :pattern
            ORDER BY created_at DESC
            """)
            .bind("pattern", "%" + searchTerm + "%")
            .map(row -> mapToMarket(row))
            .all();
    }

    public Mono<Market> findById(String id) {
        return databaseClient.sql("SELECT * FROM markets WHERE id = :id")
            .bind("id", id)
            .map(row -> mapToMarket(row))
            .one();
    }
}

// Safe - Spring Data R2DBC
public interface MarketRepository extends ReactiveCrudRepository<Market, String> {

    @Query("SELECT * FROM markets WHERE status = :status")
    Flux<Market> findByStatus(@Param("status") MarketStatus status);

    @Query("SELECT * FROM markets WHERE name ILIKE :pattern")
    Flux<Market> searchByName(@Param("pattern") String pattern);
}
```

#### Verification Steps

- [ ] All database queries use parameterized queries
- [ ] No string concatenation in SQL
- [ ] Spring Data repositories used correctly
- [ ] `@Param` annotations for named parameters
- [ ] Dynamic queries built safely with Criteria API

### 4. Authentication & Authorization

#### Spring Security WebFlux Configuration

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(csrf -> csrf.disable()) // Disable if using tokens
            .cors(cors -> cors.configurationSource(corsConfigSource()))
            .authorizeExchange(auth -> auth
                .pathMatchers("/api/public/**").permitAll()
                .pathMatchers("/api/admin/**").hasRole("ADMIN")
                .pathMatchers("/api/**").authenticated()
                .anyExchange().permitAll()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .build();
    }

    @Bean
    public CorsConfigurationSource corsConfigSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of("https://app.example.com"));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);
        
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", config);
        return source;
    }
}
```

#### JWT Token Validation

```java
@Component
public class JwtTokenProvider {

    private final SecretKey secretKey;
    private final Duration tokenValidity;

    public JwtTokenProvider(
            @Value("${jwt.secret}") String secret,
            @Value("${jwt.validity:PT1H}") Duration validity) {
        this.secretKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.tokenValidity = validity;
    }

    public String createToken(String userId, Set<String> roles) {
        Instant now = Instant.now();
        return Jwts.builder()
            .subject(userId)
            .claim("roles", roles)
            .issuedAt(Date.from(now))
            .expiration(Date.from(now.plus(tokenValidity)))
            .signWith(secretKey)
            .compact();
    }

    public Mono<Authentication> validateToken(String token) {
        return Mono.fromCallable(() -> {
            Claims claims = Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();

            String userId = claims.getSubject();
            List<String> roles = claims.get("roles", List.class);

            List<GrantedAuthority> authorities = roles.stream()
                .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .collect(Collectors.toList());

            return new UsernamePasswordAuthenticationToken(userId, null, authorities);
        }).onErrorMap(JwtException.class, e -> 
            new BadCredentialsException("Invalid token", e));
    }
}
```

#### Method-Level Security

```java
@Service
public class MarketService {

    @PreAuthorize("hasRole('ADMIN')")
    public Mono<Void> deleteMarket(String marketId) {
        return marketRepository.deleteById(marketId);
    }

    @PreAuthorize("hasRole('USER') and #userId == authentication.principal")
    public Mono<List<Order>> getUserOrders(String userId) {
        return orderRepository.findByUserId(userId).collectList();
    }

    @PreAuthorize("@securityService.canAccessMarket(#marketId, authentication)")
    public Mono<Market> getMarket(String marketId) {
        return marketRepository.findById(marketId);
    }
}

@Service
public class SecurityService {

    public boolean canAccessMarket(String marketId, Authentication auth) {
        // Custom authorization logic
        String userId = (String) auth.getPrincipal();
        return marketAccessRepository.hasAccess(userId, marketId);
    }
}
```

#### Verification Steps

- [ ] Spring Security properly configured
- [ ] JWT tokens validated with signature verification
- [ ] Token expiration checked
- [ ] Role-based access control implemented
- [ ] Method-level security with @PreAuthorize
- [ ] CORS properly configured
- [ ] HTTPS enforced in production

### 5. Rate Limiting

#### Resilience4j Rate Limiter

```java
@Configuration
public class RateLimiterConfig {

    @Bean
    public RateLimiterRegistry rateLimiterRegistry() {
        RateLimiterConfig config = RateLimiterConfig.custom()
            .limitRefreshPeriod(Duration.ofMinutes(1))
            .limitForPeriod(100) // 100 requests per minute
            .timeoutDuration(Duration.ofSeconds(5))
            .build();

        RateLimiterConfig searchConfig = RateLimiterConfig.custom()
            .limitRefreshPeriod(Duration.ofMinutes(1))
            .limitForPeriod(10) // Stricter for expensive operations
            .timeoutDuration(Duration.ofSeconds(5))
            .build();

        return RateLimiterRegistry.of(Map.of(
            "default", config,
            "search", searchConfig
        ));
    }
}

@Service
public class MarketService {

    private final RateLimiter rateLimiter;
    private final RateLimiter searchRateLimiter;

    public Mono<List<Market>> searchMarkets(String query, String userId) {
        return Mono.fromCallable(() -> searchRateLimiter.acquirePermission())
            .flatMap(permitted -> {
                if (!permitted) {
                    return Mono.error(new RateLimitExceededException("Too many search requests"));
                }
                return performSearch(query);
            });
    }
}
```

#### Per-User Rate Limiting

```java
@Component
public class RateLimitingFilter implements WebFilter {

    private final Cache<String, AtomicInteger> requestCounts = Caffeine.newBuilder()
        .expireAfterWrite(Duration.ofMinutes(1))
        .build();

    private static final int MAX_REQUESTS_PER_MINUTE = 100;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String clientId = extractClientId(exchange);

        AtomicInteger count = requestCounts.get(clientId, k -> new AtomicInteger(0));

        if (count.incrementAndGet() > MAX_REQUESTS_PER_MINUTE) {
            exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
            return exchange.getResponse().setComplete();
        }

        return chain.filter(exchange);
    }

    private String extractClientId(ServerWebExchange exchange) {
        // Prefer user ID if authenticated, fallback to IP
        return exchange.getPrincipal()
            .map(Principal::getName)
            .defaultIfEmpty(getClientIp(exchange.getRequest()))
            .block();
    }
}
```

#### Verification Steps

- [ ] Rate limiting on all API endpoints
- [ ] Stricter limits on expensive operations (search, AI calls)
- [ ] Per-user rate limiting for authenticated users
- [ ] IP-based rate limiting for anonymous users
- [ ] Rate limit headers returned in response

### 6. Sensitive Data Protection

#### Logging - NEVER Log Secrets

```java
// WRONG: Logging sensitive data
log.info("User login: email={}, password={}", email, password);
log.debug("Payment: cardNumber={}, cvv={}", cardNumber, cvv);
log.error("API call failed with key: {}", apiKey);

// CORRECT: Redact or omit sensitive data
log.info("User login: email={}", email);
log.debug("Payment processed for user: {}, last4: {}", userId, cardLast4);
log.error("API call failed for service: {}", serviceName);
```

#### Use @JsonIgnore and Masking

```java
public record User(
    String id,
    String email,
    @JsonIgnore String passwordHash,
    @JsonIgnore String apiToken
) {}

// Or use a DTO for responses
public record UserResponse(
    String id,
    String email,
    String maskedPhone  // "***-***-1234"
) {
    public static UserResponse from(User user) {
        return new UserResponse(
            user.id(),
            user.email(),
            maskPhone(user.phone())
        );
    }
}
```

#### Secure Error Responses

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    // WRONG: Exposing internal details
    // return new ErrorResponse(ex.getMessage(), ex.getStackTrace());

    // CORRECT: Generic error messages
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(Exception ex) {
        // Log full error internally
        log.error("Unexpected error", ex);

        // Return generic message to user
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse(
                "INTERNAL_ERROR",
                "An error occurred. Please try again."
            ));
    }

    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<ErrorResponse> handleDatabaseError(DataAccessException ex) {
        log.error("Database error", ex);

        // Never expose database details
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse(
                "SERVICE_ERROR",
                "Service temporarily unavailable"
            ));
    }
}
```

#### Verification Steps

- [ ] No passwords, tokens, or secrets in logs
- [ ] PII masked or excluded from logs
- [ ] @JsonIgnore on sensitive fields
- [ ] DTOs used for API responses
- [ ] Error messages generic for users
- [ ] Stack traces only in internal logs
- [ ] Audit logging for sensitive operations

### 7. Dependency Security

#### Regular Updates

```bash
# Check for vulnerabilities with Gradle
./gradlew dependencyCheckAnalyze

# Update dependencies
./gradlew dependencyUpdates

# Use OWASP dependency-check
plugins {
    id 'org.owasp.dependencycheck' version '8.4.0'
}

dependencyCheck {
    failBuildOnCVSS = 7  # Fail build on high severity
    suppressionFile = "owasp-suppressions.xml"
}
```

#### Build Configuration

```kotlin
// build.gradle.kts
plugins {
    id("org.owasp.dependencycheck") version "8.4.0"
    id("com.github.ben-manes.versions") version "0.48.0"
}

dependencyCheck {
    failBuildOnCVSS = 7f
    analyzers.apply {
        assemblyEnabled = false
        nodeEnabled = false
    }
}

// Ensure consistent dependency versions
dependencyManagement {
    imports {
        mavenBom("org.springframework.boot:spring-boot-dependencies:3.2.0")
        mavenBom("org.springframework.cloud:spring-cloud-dependencies:2023.0.0")
    }
}
```

#### Verification Steps

- [ ] Dependencies up to date
- [ ] No known vulnerabilities (OWASP check passes)
- [ ] gradle.lockfile or dependency versions pinned
- [ ] Dependabot/Renovate enabled on GitHub
- [ ] Regular security updates scheduled

### 8. Security Headers

```java
@Component
public class SecurityHeadersFilter implements WebFilter {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        ServerHttpResponse response = exchange.getResponse();
        HttpHeaders headers = response.getHeaders();

        // Prevent clickjacking
        headers.add("X-Frame-Options", "DENY");

        // Prevent MIME type sniffing
        headers.add("X-Content-Type-Options", "nosniff");

        // Enable XSS protection
        headers.add("X-XSS-Protection", "1; mode=block");

        // Strict Transport Security (HTTPS only)
        headers.add("Strict-Transport-Security", "max-age=31536000; includeSubDomains");

        // Content Security Policy
        headers.add("Content-Security-Policy", "default-src 'self'");

        // Referrer Policy
        headers.add("Referrer-Policy", "strict-origin-when-cross-origin");

        return chain.filter(exchange);
    }
}
```

## Pre-Deployment Security Checklist

Before ANY production deployment:

### Secrets & Configuration

- [ ] No hardcoded secrets in code
- [ ] All secrets in environment variables or secret manager
- [ ] Production config separate from development
- [ ] .gitignore includes all sensitive files

### Input Handling

- [ ] All user inputs validated (Bean Validation)
- [ ] File uploads restricted (size, type, extension)
- [ ] Path traversal attacks prevented
- [ ] JSON deserialization secured (no @JsonTypeInfo without whitelist)

### Database Security

- [ ] All queries parameterized (no SQL string concatenation)
- [ ] Database credentials in secrets manager
- [ ] Least privilege database user
- [ ] Connection pooling configured

### Authentication & Authorization

- [ ] JWT tokens properly validated
- [ ] Token expiration enforced
- [ ] Role-based access control in place
- [ ] Method-level security enabled

### API Security

- [ ] HTTPS enforced
- [ ] CORS properly configured
- [ ] Rate limiting on all endpoints
- [ ] Security headers configured
- [ ] API versioning implemented

### Logging & Monitoring

- [ ] No sensitive data in logs
- [ ] Audit logging for sensitive operations
- [ ] Error monitoring configured
- [ ] Security alerts enabled

### Dependencies

- [ ] All dependencies up to date
- [ ] No known vulnerabilities
- [ ] Dependency scanning in CI/CD

## Security Testing

```java
@SpringBootTest
@AutoConfigureWebTestClient
class SecurityTest {

    @Autowired
    private WebTestClient webTestClient;

    @Test
    @DisplayName("Protected endpoint requires authentication")
    void protectedEndpointRequiresAuth() {
        webTestClient.get()
            .uri("/api/protected")
            .exchange()
            .expectStatus().isUnauthorized();
    }

    @Test
    @DisplayName("Admin endpoint requires admin role")
    void adminEndpointRequiresAdminRole() {
        webTestClient.get()
            .uri("/api/admin/users")
            .headers(h -> h.setBearerAuth(regularUserToken))
            .exchange()
            .expectStatus().isForbidden();
    }

    @Test
    @DisplayName("Invalid JWT is rejected")
    void invalidJwtRejected() {
        webTestClient.get()
            .uri("/api/protected")
            .headers(h -> h.setBearerAuth("invalid.token.here"))
            .exchange()
            .expectStatus().isUnauthorized();
    }

    @Test
    @DisplayName("Input validation rejects invalid data")
    void inputValidationWorks() {
        var invalidRequest = Map.of("email", "not-an-email");

        webTestClient.post()
            .uri("/api/users")
            .bodyValue(invalidRequest)
            .exchange()
            .expectStatus().isBadRequest()
            .expectBody()
            .jsonPath("$.code").isEqualTo("VALIDATION_ERROR");
    }

    @Test
    @DisplayName("Rate limiting enforced")
    void rateLimitingWorks() {
        // Make requests up to limit
        for (int i = 0; i < 100; i++) {
            webTestClient.get()
                .uri("/api/public/health")
                .exchange()
                .expectStatus().isOk();
        }

        // Next request should be rate limited
        webTestClient.get()
            .uri("/api/public/health")
            .exchange()
            .expectStatus().isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
    }
}
```

## Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Spring Security Reference](https://docs.spring.io/spring-security/reference/)
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
- [CWE - Common Weakness Enumeration](https://cwe.mitre.org/)

---

**Remember**: Security is not optional. One vulnerability can compromise the entire platform. When in doubt, err on the
side of caution.
