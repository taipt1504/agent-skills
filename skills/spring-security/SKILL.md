---
name: spring-security
description: Spring Security patterns — authentication, authorization, JWT, CORS, secrets management, OWASP scanning, security review for MVC and WebFlux applications. Use when configuring SecurityFilterChain or SecurityWebFilterChain, implementing JWT authentication, setting up CORS, applying method-level security, managing secrets, or reviewing OWASP compliance.
triggers:
  natural: ["jwt auth", "cors config", "security filter", "oauth", "authentication"]
  code: ["SecurityConfig", "@PreAuthorize", "JWT", "@AuthRoles"]
applicability:
  always: false
  triggers:
    files_match: ["**/*SecurityConfig*.java", "**/*AuthConfig*.java", "**/*JwtConfig*.java", "**/*CorsConfig*.java"]
    code_patterns: ["SecurityFilterChain", "SecurityWebFilterChain", "@PreAuthorize", "@EnableReactiveMethodSecurity", "@EnableMethodSecurity", "PasswordEncoder"]
    task_keywords: ["security", "auth", "OAuth", "JWT", "CORS", "CSRF", "Keycloak", "SAML", "RBAC", "authorization"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
      - rules/java/reactive.md
relevance_assessment: |
  HIGH 90%+: SecurityFilterChain edit OR auth flow change OR @PreAuthorize add
  HIGH 80%+: CORS allowlist OR JWT config tweak
  MEDIUM 40-79%: endpoint added to existing auth scheme
  LOW 1-39%: caller of secured method, no auth change
  ZERO: no Spring Security dep (verify build.gradle)
---

# Spring Security

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

**MVC** — `SecurityFilterChain`, `HttpSecurity`, `OncePerRequestFilter` for JWT, `@EnableWebSecurity`, `@EnableMethodSecurity`.

**WebFlux** — `SecurityWebFilterChain`, `ServerHttpSecurity`, `@EnableWebFluxSecurity`, `@EnableReactiveMethodSecurity`, `oauth2ResourceServer` with JWT converter.

Both: CSRF disabled (stateless), stateless sessions, explicit CORS origins (never `*`), BCrypt >= 12.

## Secrets Management

- `@ConfigurationProperties` with `@Validated` — map `${ENV_VAR}` references
- Never hardcode secrets; never commit `application-local.yml`
- `.gitignore`: `.env`, `*.pem`, `*.key`, `application-local.yml`, `application-secret.yml`
- Production: Vault / AWS Secrets Manager / K8s Secrets

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

- **[references/jwt-auth.md](references/jwt-auth.md)** — JWT filter (MVC), SecurityFilterChain, SecurityWebFilterChain, token provider, method security
- **[references/oauth2-oidc.md](references/oauth2-oidc.md)** — OAuth2 resource server, client credentials, principal extraction, Spring Security 6.x migration, mockJwt()
- **[references/cors-headers.md](references/cors-headers.md)** — CORS (MVC + WebFlux), security headers filter
- **[references/security-testing.md](references/security-testing.md)** — MockMvc + WebTestClient security tests, OWASP dep scanning
- **[references/file-upload-secrets.md](references/file-upload-secrets.md)** — File upload validation, path traversal, secrets management

## Related Skills

- **redis-patterns** — Redis-based rate limiting
- **spring-webflux-patterns** — Resilience4j rate limiting, WebFilter setup
- **pentest** — Security scanning, OWASP Top 10 assessment
- **summer-security** — APISIX auth, Keycloak integration (Summer projects)
