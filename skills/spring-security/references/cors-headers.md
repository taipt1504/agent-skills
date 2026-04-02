# CORS, Security Headers Reference

CORS configuration and security headers for MVC and WebFlux.

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

### WebFlux (inside SecurityWebFilterChain)

```java
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
```

### Anti-Pattern

```java
// BAD: Wildcard CORS -- allows any origin
config.setAllowedOrigins(List.of("*"));
config.addAllowedOriginPattern("*");     // Same problem
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
