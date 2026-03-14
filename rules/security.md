# Security Guidelines

## Mandatory Security Checks

Before ANY commit:

- [ ] No hardcoded secrets (API keys, passwords, tokens, DB credentials)
- [ ] All user inputs validated (Bean Validation, custom validators)
- [ ] SQL injection prevention (R2DBC parameterized queries, no string concat)
- [ ] No sensitive data in logs
- [ ] CSRF protection enabled (Spring Security)
- [ ] Authentication/authorization verified on all endpoints
- [ ] Rate limiting on public/critical endpoints
- [ ] Error messages don't leak sensitive data (stack traces, SQL errors)
- [ ] Dependencies checked for CVEs (`./gradlew dependencyCheckAnalyze`)

## Secret Management

```java
// ❌ NEVER: Hardcoded secrets
private static final String API_KEY = "sk-proj-xxxxx";
private static final String DB_PASSWORD = "admin123";

// ✅ ALWAYS: External configuration
@Value("${api.openai.key}")
private String apiKey;

// ✅ BETTER: Type-safe configuration
@ConfigurationProperties(prefix = "api.openai")
@Validated
public class OpenAiProperties {
    @NotBlank
    private String key;
    
    @NotBlank  
    private String model;
}

// ✅ BEST: Use secrets manager (Vault, AWS Secrets Manager)
```

### Environment Configuration

```yaml
# application.yml - use placeholders
spring:
  r2dbc:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}

api:
  openai:
    key: ${OPENAI_API_KEY}
    
# ❌ NEVER commit real values
# ✅ Use .env files (add to .gitignore)
# ✅ Use CI/CD secrets injection
```

## SQL Injection Prevention

```java
// ❌ CRITICAL: SQL Injection vulnerability
public Flux<Order> findByStatus(String status) {
    String query = "SELECT * FROM orders WHERE status = '" + status + "'";
    return databaseClient.sql(query).fetch().all();
}

// ✅ CORRECT: Parameterized query
public Flux<Order> findByStatus(String status) {
    return databaseClient
        .sql("SELECT * FROM orders WHERE status = :status")
        .bind("status", status)
        .fetch().all();
}

// ✅ CORRECT: Using R2DBC Repository
public interface OrderRepository extends ReactiveCrudRepository<Order, String> {
    Flux<Order> findByStatus(OrderStatus status);
}
```

## Authentication & Authorization

### Secure Endpoints

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
public class SecurityConfig {
    
    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(csrf -> csrf.csrfTokenRepository(
                CookieServerCsrfTokenRepository.withHttpOnlyFalse()))
            .authorizeExchange(auth -> auth
                .pathMatchers("/api/public/**").permitAll()
                .pathMatchers("/api/admin/**").hasRole("ADMIN")
                .pathMatchers("/actuator/health").permitAll()
                .pathMatchers("/actuator/**").hasRole("ADMIN")
                .anyExchange().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(Customizer.withDefaults()))
            .build();
    }
}
```

### Method-Level Security

```java
@Service
public class OrderService {
    
    @PreAuthorize("hasRole('ADMIN') or #customerId == authentication.principal.id")
    public Mono<Order> findByCustomerId(String customerId) {
        return orderRepository.findByCustomerId(customerId);
    }
    
    @PreAuthorize("hasRole('ADMIN')")
    public Mono<Void> deleteOrder(String orderId) {
        return orderRepository.deleteById(orderId);
    }
}
```

## Rate Limiting

```java
// Using Resilience4j
@Bean
public RateLimiterConfig rateLimiterConfig() {
    return RateLimiterConfig.custom()
        .limitForPeriod(100)           // 100 calls
        .limitRefreshPeriod(Duration.ofSeconds(1))  // per second
        .timeoutDuration(Duration.ofMillis(500))
        .build();
}

@RateLimiter(name = "api")
@GetMapping("/api/orders")
public Flux<Order> getOrders() {
    return orderService.findAll();
}
```

## Logging Security

```java
// ❌ NEVER: Log sensitive data
log.info("User login: {} with password: {}", username, password);
log.debug("Request: {}", requestWithCreditCard);

// ✅ CORRECT: Sanitize logs
log.info("User login attempt: {}", maskEmail(username));
log.debug("Processing order: {}", orderId);  // Only ID, not full object

// ✅ Use MDC for tracing (not sensitive data)
MDC.put("userId", userId);
MDC.put("orderId", orderId);
```

## Error Response Security

```java
// ❌ NEVER: Expose internal errors
@ExceptionHandler(Exception.class)
public ErrorResponse handleException(Exception ex) {
    return new ErrorResponse(ex.getMessage(), ex.getStackTrace());  // Leaks info!
}

// ✅ CORRECT: Safe error responses
@ExceptionHandler(Exception.class)
public Mono<ResponseEntity<ErrorResponse>> handleException(Exception ex) {
    log.error("Internal error", ex);  // Log full error internally
    
    return Mono.just(ResponseEntity
        .status(HttpStatus.INTERNAL_SERVER_ERROR)
        .body(new ErrorResponse(
            "INTERNAL_ERROR",
            "An unexpected error occurred"  // Generic message to client
        )));
}

@ExceptionHandler(DataAccessException.class)
public Mono<ResponseEntity<ErrorResponse>> handleDbError(DataAccessException ex) {
    log.error("Database error", ex);
    
    return Mono.just(ResponseEntity
        .status(HttpStatus.INTERNAL_SERVER_ERROR)
        .body(new ErrorResponse(
            "SERVICE_UNAVAILABLE",
            "Service temporarily unavailable"  // Don't mention DB!
        )));
}
```

## Dependency Security

```bash
# Check for vulnerable dependencies
./gradlew dependencyCheckAnalyze

# View report
open build/reports/dependency-check-report.html

# Add to CI/CD pipeline
# Fail build if high/critical vulnerabilities found
```

```groovy
// build.gradle
plugins {
    id 'org.owasp.dependencycheck' version '9.0.0'
}

dependencyCheck {
    failBuildOnCVSS = 7  // Fail on HIGH or CRITICAL
    suppressionFile = 'dependency-check-suppressions.xml'
}
```

## Security Response Protocol

If security issue found:

1. **STOP** immediately
2. **Use security-reviewer agent** for full analysis
3. **Fix CRITICAL issues** before any other work
4. **Rotate exposed secrets** immediately:
    - Generate new API keys
    - Change database passwords
    - Invalidate JWT signing keys
5. **Review entire codebase** for similar issues
6. **Update dependencies** if CVE found
7. **Document incident** and preventive measures

## Security Checklist by Component

### Controllers

- [ ] `@Valid` on all request bodies
- [ ] No sensitive data in URL parameters
- [ ] Proper HTTP methods (GET safe, POST/PUT/DELETE for changes)
- [ ] Authorization checks (`@PreAuthorize`)

### Services

- [ ] Input validation before processing
- [ ] No logging of sensitive data
- [ ] Transaction boundaries properly defined
- [ ] Rate limiting on critical operations

### Repositories

- [ ] Parameterized queries only
- [ ] No string concatenation in SQL
- [ ] Proper field-level security

### Configuration

- [ ] All secrets from environment
- [ ] HTTPS enforced in production
- [ ] CORS properly configured
- [ ] Security headers set
