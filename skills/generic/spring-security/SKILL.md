---
name: spring-security
description: Spring Security patterns — authentication, authorization, JWT, CORS, secrets management, OWASP scanning, security review for MVC and WebFlux applications
triggers:
  - Security config (SecurityFilterChain, SecurityWebFilterChain)
  - JWT authentication or token handling
  - CORS configuration
  - "@PreAuthorize or method-level security"
  - Secrets management, hardcoded credentials
  - OWASP dependency scanning or vulnerability review
---

# Spring Security

Activate when touching: authentication, authorization, JWT, CORS, secrets, file uploads, API endpoints, payments, PII, or OWASP scanning.

## OWASP Top 10 Quick Rules

| Rule | Critical Pattern |
|------|-----------------|
| **No hardcoded secrets** | `@ConfigurationProperties` + env vars / Vault |
| **Parameterized queries** | `.bind("param", value)` -- never concatenate SQL |
| **Validate all inputs** | `@Valid @RequestBody` + Bean Validation |
| **JWT validation** | Verify signature + expiry; `Keys.hmacShaKeyFor()` |
| **CORS locked down** | Explicit `setAllowedOrigins(List.of("https://..."))` |
| **@JsonIgnore secrets** | On passwordHash, creditCard in all domain objects |
| **Generic error messages** | Never expose stack traces, SQL errors, or keys |
| **Rate limiting** | Every endpoint -- 100 req/min default, stricter for sensitive ops |
| **File type whitelist** | Validate extension + magic bytes + size (max 5MB) |
| **Path traversal** | `resolved.startsWith(uploadDir)` before file reads |

## Security Config

**MVC** -- `SecurityFilterChain` with `HttpSecurity`, custom `OncePerRequestFilter` for JWT, `@EnableWebSecurity`, `@EnableMethodSecurity`.

**WebFlux** -- `SecurityWebFilterChain` with `ServerHttpSecurity`, `@EnableWebFluxSecurity`, `@EnableReactiveMethodSecurity`, `oauth2ResourceServer` with JWT converter.

Both: disable CSRF for stateless APIs, stateless sessions, explicit CORS origins (never `*`), BCrypt cost >= 12.

## Secrets Management

- `@ConfigurationProperties` with `@Validated` -- map `${ENV_VAR}` references
- Never hardcode secrets; never commit `application-local.yml`
- `.gitignore`: `.env`, `*.pem`, `*.key`, `application-local.yml`, `application-secret.yml`
- Production: Vault / AWS Secrets Manager / K8s secrets

## Pre-Deployment Checklist

- [ ] No hardcoded secrets in source or git history
- [ ] JWT secret from env var; BCrypt cost >= 12
- [ ] CORS: explicit origins, no wildcards
- [ ] `@PreAuthorize` on sensitive methods
- [ ] `@Valid` on all request bodies; file upload whitelist
- [ ] Parameterized queries only (zero SQL concatenation)
- [ ] Rate limiting on auth + expensive endpoints
- [ ] Security headers: HSTS, X-Frame-Options, CSP, nosniff
- [ ] OWASP scan passes (`failBuildOnCVSS=7`)
- [ ] No PII/tokens/credentials in logs
- [ ] Actuator: only health/info public
- [ ] No `@Disabled` security tests

## Anti-Patterns

```java
// BAD: SQL injection
String sql = "SELECT * FROM users WHERE name = '" + name + "'";
// GOOD: databaseClient.sql("SELECT ... WHERE name = :name").bind("name", name)

// BAD: Secret in code
private static final String API_KEY = "sk-proj-xxxx";
// GOOD: @Value("${app.api-key}") private String apiKey;

// BAD: Wildcard CORS
config.setAllowedOrigins(List.of("*"));
// GOOD: config.setAllowedOrigins(List.of("https://app.example.com"));

// BAD: Exposing internals
return new ErrorResponse(ex.getMessage(), ex.getStackTrace());
// GOOD: ProblemDetail.forStatusAndDetail(500, "An unexpected error occurred");
```

## References

Load as needed:

- **[references/security-patterns.md](references/security-patterns.md)** -- Full code examples: JWT filter (MVC), SecurityFilterChain (MVC), SecurityWebFilterChain (WebFlux), method security, CORS config, file upload validation, path traversal prevention, JWT token provider, rate limiting (Caffeine + Resilience4j), sensitive data logging, security headers filter, security testing (MockMvc + WebTestClient), OWASP dependency scanning
