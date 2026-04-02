---
name: security
description: Security rules — OWASP-aligned, Spring Security 6.x patterns, secrets management, supply chain security
globs: "*.java,*.yml,*.yaml,*.properties"
---

# Security Rules

## Hard Blocks (STOP immediately)

| Violation | Why It's Critical | Fix |
|-----------|-------------------|-----|
| Hardcoded secrets in source | Secrets in git history are permanent — even after deletion, they persist in commits. Attackers actively scan public repos. | `@ConfigurationProperties` + env vars / Vault |
| String concatenation in SQL | SQL injection is OWASP #3 — attackers can dump entire databases or escalate privileges through crafted input. | `.bind("param", value)` or Spring Data derived queries |
| `.block()` in security filter chain | Blocking the Netty event loop in a security filter deadlocks all concurrent requests — total service outage. | Reactive `SecurityWebFilterChain` with `Mono`/`Flux` |
| Exposed stack traces in API responses | Stack traces leak class names, library versions, and SQL structure — attackers use this for targeted exploits. | `@RestControllerAdvice` + `ProblemDetail` (RFC 7807) |
| `WebSecurityConfigurerAdapter` usage | Deprecated in Spring Security 5.7, removed in 6.0. Prevents migration to component-based security. | `SecurityFilterChain` @Bean method |

## Pre-Commit Checklist

- [ ] No hardcoded secrets (API keys, passwords, tokens, DB credentials)
- [ ] All user inputs validated (`@Valid` + Bean Validation at API boundary)
- [ ] SQL injection prevention (parameterized queries, no string concatenation)
- [ ] No sensitive data in logs (PII, credentials, tokens, full request bodies)
- [ ] Auth/authz on all endpoints except health checks
- [ ] Error messages don't leak internals (stack traces, SQL errors, class names)
- [ ] CORS explicitly configured (never wildcard `*` in production)
- [ ] Dependencies scanned for known CVEs

## NEVER / ALWAYS

| Category | NEVER | ALWAYS | Why |
|----------|-------|--------|-----|
| Secrets | Hardcode in source or config files | `@ConfigurationProperties` + env vars / Vault / Spring Cloud Config | Secrets in git are permanent; env vars are runtime-only |
| SQL | String concatenation in queries | `.bind("param", value)` or Spring Data methods | SQL injection enables full DB access |
| CORS | Wildcard `*` in production | Explicit `setAllowedOrigins(List.of("https://..."))` | Wildcard enables CSRF from any origin |
| Errors | Expose stack traces, SQL, or class names | Generic user message; log full error internally with correlation ID | Attackers use internal details to craft exploits |
| Logging | Log passwords, tokens, PII, credit cards | Mask sensitive data; use MDC correlation for tracing | Log aggregators have broad access; leaked PII violates GDPR/CCPA |
| Auth | Unprotected endpoints (except `/actuator/health`) | `@PreAuthorize` on sensitive methods + path-based security | Missing auth is OWASP #1 — Broken Access Control |
| Files | Accept uploads without validation | Whitelist extension + MIME type + size limit (max 10MB default) | Unrestricted upload enables RCE via malicious files |
| Passwords | Weak or deprecated encoding (MD5, SHA-1, bcrypt<10 rounds) | `Argon2idPasswordEncoder` or PBKDF2 with high iteration count | Weak hashing enables offline brute-force attacks |
| TLS | HTTP for any API (even internal) | HTTPS/TLS 1.2+ everywhere; `server.ssl.*` configured | Unencrypted traffic exposes credentials and data in transit |

## Spring Security 6.x Patterns

Use `SecurityFilterChain` bean — never extend deprecated `WebSecurityConfigurerAdapter`:

```java
@Bean
public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
    return http
        .csrf(ServerHttpSecurity.CsrfSpec::disable)  // disable only for stateless APIs
        .authorizeExchange(auth -> auth
            .pathMatchers("/actuator/health").permitAll()
            .anyExchange().authenticated())
        .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
        .build();
}
```

Enable method-level security with `@EnableReactiveMethodSecurity`:
```java
@PreAuthorize("hasAnyRole(@roles.ADMIN)")
public Mono<UserProfile> getAdminProfile(String userId) { ... }
```

## Supply Chain Security

Modern attacks increasingly target dependencies, not application code:

- **SBOM generation**: Spring Boot 3.3+ auto-generates CycloneDX SBOMs. Include in CI/CD pipeline.
- **Dependency scanning**: Integrate OWASP Dependency-Check or Snyk in Gradle: `dependencyCheckAnalyze`.
- **Version pinning**: Use `dependencyManagement` to lock transitive dependency versions.
- **Audit regularly**: `./gradlew dependencyUpdates` to identify outdated libraries with known CVEs.

## Component Security by Layer

**Controllers** — `@Valid` on all request bodies; `@PreAuthorize` checks; no sensitive data in URL query params (use request body or headers); rate limiting on auth endpoints.

**Services** — Input validation before processing; no logging of sensitive data; idempotency keys on mutation operations; rate limiting on critical operations (OTP, password reset).

**Repositories** — Parameterized queries only; least-privilege DB user (separate read/write users); no `SELECT *` — explicit column selection.

**Configuration** — Secrets from env vars or Vault; HTTPS enforced; CORS explicit allowlist; security headers set (CSP, X-Frame-Options, X-Content-Type-Options); actuator endpoints secured (only `/health` public).

## Response Protocol

If security issue found: **STOP** → assess severity → fix CRITICAL issues immediately → rotate any exposed secrets → scan codebase for similar patterns → use reviewer agent for validation.

## Related Skills

- **spring-security** — Full SecurityWebFilterChain patterns, JWT, CORS config
- **summer-security** — APISIX auth, @AuthRoles, Keycloak integration
- **pentest** — OWASP Top 10 scanning, CVE detection
- **observability-patterns** — Security event logging, audit trails
