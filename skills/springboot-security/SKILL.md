---
name: springboot-security
description: Spring Security patterns — JWT filter, SecurityFilterChain, method security, CORS, secrets management, OWASP scanning
---

# Spring Boot Security

## When to Activate

- Configuring Spring Security (filter chains, authentication)
- Implementing JWT-based authentication
- Reviewing CORS, CSRF, or method-level security
- Checking for hardcoded secrets or credential exposure
- Pre-release security review

## JWT Authentication Filter

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

## Security Filter Chain

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

## Method Security

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    // Only order owner or admin can view
    @PreAuthorize("@orderSecurity.isOwner(#id, authentication) or hasRole('ADMIN')")
    public OrderDto findById(Long id) { ... }

    // Only authenticated users can create
    @PreAuthorize("isAuthenticated()")
    public OrderDto createOrder(CreateOrderCommand command) { ... }

    // Filter results post-execution
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

## CORS Configuration

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

```java
// BAD: Wildcard CORS
config.setAllowedOrigins(List.of("*")); // Allows any origin
config.addAllowedOriginPattern("*");     // Same problem
```

## Secrets Management

### @ConfigurationProperties (Recommended)

```java
@ConfigurationProperties(prefix = "app.jwt")
@Validated
public record JwtProperties(
    @NotBlank String secret,
    @Positive long expirationMs,
    @NotBlank String issuer
) {}

// application.yml — reference env vars, never hardcode
app:
  jwt:
    secret: ${JWT_SECRET}
    expiration-ms: ${JWT_EXPIRATION:3600000}
    issuer: ${JWT_ISSUER:my-app}
```

### What to Check

```java
// BAD: Hardcoded secrets
private static final String SECRET = "mySecretKey123";
private static final String DB_PASSWORD = "postgres";

// BAD: Secrets in application.yml committed to git
spring:
  datasource:
    password: actualPassword123

// GOOD: Environment variable references
spring:
  datasource:
    password: ${DB_PASSWORD}
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

## OWASP Dependency Scanning

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

## Pre-Release Security Checklist

- [ ] No hardcoded secrets in source code (`grep -r "password\|secret\|api.key" src/`)
- [ ] JWT secret from environment variable, not config file
- [ ] BCrypt cost factor >= 12 for password hashing
- [ ] CORS whitelist explicit origins (no wildcards)
- [ ] CSRF disabled only for stateless APIs
- [ ] Rate limiting on authentication endpoints
- [ ] `@PreAuthorize` on sensitive service methods
- [ ] OWASP dependency scan passes (no HIGH/CRITICAL CVEs)
- [ ] `.env` and credential files in `.gitignore`
- [ ] Actuator endpoints secured (only health/info public)
- [ ] SQL injection: parameterized queries only (no string concatenation)
- [ ] Input validation: `@Valid` on all request bodies
- [ ] No `@Disabled` security tests
- [ ] Logging: no PII, no credentials, no tokens in logs
