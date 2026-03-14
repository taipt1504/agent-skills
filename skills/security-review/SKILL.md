---
name: security-review
description: Use this skill when adding authentication, handling user input, working with secrets, creating API endpoints, or implementing payment/sensitive features. Provides comprehensive security checklist and patterns for Java Spring applications.
---

# Security Review

Use proactively whenever touching: authentication, user input, file uploads, API endpoints, secrets, payments, PII, third-party APIs, or database queries.

## OWASP Top 10 Quick Rules

| Rule | Critical Pattern |
|------|-----------------|
| **No hardcoded secrets** | Use `@Value("${secret}")` + env vars / Vault |
| **Parameterized queries** | Always `.bind("param", value)` — never concatenate SQL |
| **Validate all inputs** | `@Valid @RequestBody` + Bean Validation annotations |
| **JWT validation** | Verify signature + expiry; use `Keys.hmacShaKeyFor()` |
| **CORS locked down** | Explicit `setAllowedOrigins(List.of("https://..."))` |
| **@JsonIgnore secrets** | `@JsonIgnore String passwordHash` on all domain objects |
| **Generic error messages** | Never expose stack traces, SQL errors, or keys to clients |
| **Rate limiting** | Every endpoint — 100 req/min default, stricter for expensive ops |
| **File type whitelist** | Validate extension + MIME type + size (max 5MB) |
| **Path traversal** | `filePath.startsWith(uploadDir)` check before file reads |

---

## Pre-Deployment Checklist

### Secrets & Configuration
- [ ] No hardcoded API keys, tokens, or passwords anywhere in code
- [ ] All secrets in environment variables or secret manager (Vault/AWS SM/K8s)
- [ ] `application-local.yml` in `.gitignore`
- [ ] No secrets in git history

### Input Handling
- [ ] All user inputs validated with Bean Validation (`@Valid`)
- [ ] File uploads: type whitelist, size limit, extension check
- [ ] Path traversal prevented (`filePath.startsWith(uploadDir)`)
- [ ] No blacklist validation — always use whitelist

### Database Security
- [ ] All queries parameterized (zero string concatenation in SQL)
- [ ] Database credentials via secrets manager
- [ ] Least privilege database user

### Authentication & Authorization
- [ ] JWT tokens validated with signature verification
- [ ] Token expiration enforced
- [ ] `@PreAuthorize` on sensitive methods
- [ ] `@EnableReactiveMethodSecurity` on config class

### API Security
- [ ] HTTPS enforced in production
- [ ] CORS: explicit allowed origins (no wildcard `*` in production)
- [ ] Rate limiting on all endpoints
- [ ] Security headers: `X-Frame-Options`, `X-Content-Type-Options`, `HSTS`

### Logging & Monitoring
- [ ] No passwords, tokens, or secrets in logs
- [ ] PII masked or excluded from logs
- [ ] Error messages generic for users (not internal details)
- [ ] Audit logging for sensitive operations (login, payment, admin actions)

### Dependencies
- [ ] No known CVEs (`./gradlew dependencyCheckAnalyze` — failBuildOnCVSS=7)
- [ ] Dependency scanning in CI/CD (Dependabot/Renovate enabled)

---

## Spring Security Config (WebFlux)

```java
@Configuration @EnableWebFluxSecurity @EnableReactiveMethodSecurity
public class SecurityConfig {
    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(csrf -> csrf.disable())  // API-only service
            .cors(cors -> cors.configurationSource(corsConfigSource()))
            .authorizeExchange(auth -> auth
                .pathMatchers("/api/public/**").permitAll()
                .pathMatchers("/actuator/health", "/actuator/info").permitAll()
                .pathMatchers("/api/admin/**").hasRole("ADMIN")
                .anyExchange().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .build();
    }
}
```

---

## Key Anti-Patterns

```java
// ❌ SQL injection risk
String sql = "SELECT * FROM users WHERE name = '" + name + "'";

// ✅ Parameterized
databaseClient.sql("SELECT * FROM users WHERE name = :name").bind("name", name)

// ❌ Secret in code
private static final String API_KEY = "sk-proj-xxxx";

// ✅ From environment
@Value("${app.api-key}") private String apiKey;

// ❌ Exposing internals in error
return new ErrorResponse(ex.getMessage(), ex.getStackTrace());

// ✅ Generic user-facing message
log.error("Unexpected error", ex);
return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR,
    "An unexpected error occurred");

// ❌ Wildcard CORS
config.setAllowedOrigins(List.of("*"));

// ✅ Explicit origin
config.setAllowedOrigins(List.of("https://app.example.com"));
```

---

## References

Load as needed:

- **[references/security-patterns.md](references/security-patterns.md)** — Full code examples: secrets config, file validation, path traversal, JWT token provider, method security, rate limiting (Resilience4j + per-user), sensitive data logging, security headers filter, security testing with WebTestClient
