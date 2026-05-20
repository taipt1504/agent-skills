---
name: security-java
description: Java/Spring Security 6.x patterns — SecurityFilterChain, @PreAuthorize, password encoders, layered security.
globs: "*.java,*.yml,*.yaml,*.properties"
applicability:
  always: false
  triggers:
    files_match: ["**/*.java", "**/*.yml", "**/*.yaml", "**/application*.properties"]
    code_patterns: ["SecurityFilterChain", "SecurityWebFilterChain", "@PreAuthorize", "WebSecurityConfigurer", "PasswordEncoder"]
    task_keywords: ["security", "auth", "oauth", "jwt", "csrf", "cors"]
---

# Security — Java/Spring

> Inherits `rules/common/security.md`. Below = Spring-specific patterns.

## Spring Security 6.x — SecurityFilterChain

NEVER extend deprecated `WebSecurityConfigurerAdapter` (removed in 6.0). Use bean method:

```java
@Bean
public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
    return http
        .csrf(ServerHttpSecurity.CsrfSpec::disable)  // stateless APIs only
        .authorizeExchange(auth -> auth
            .pathMatchers("/actuator/health").permitAll()
            .anyExchange().authenticated())
        .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
        .build();
}
```

## Method-Level Security

Enable `@EnableReactiveMethodSecurity` (or `@EnableMethodSecurity` for MVC):

```java
@PreAuthorize("hasAnyRole(@roles.ADMIN)")
public Mono<UserProfile> getAdminProfile(String userId) { ... }
```

## Password Encoding

- `Argon2idPasswordEncoder` — preferred for new systems
- PBKDF2 with high iteration count — acceptable
- NEVER MD5, SHA-1, bcrypt with rounds < 10

## Reactive Security — No .block()

`.block()` in security filter deadlocks all concurrent requests → total outage. Reactive `SecurityWebFilterChain` with `Mono`/`Flux` only. See `rules/java/reactive.md`.

## Layered Security

**Controllers** — `@Valid`; `@PreAuthorize`; no sensitive data in URL params; rate limit auth endpoints.

**Services** — Validate input; no sensitive data in logs; idempotency keys on mutations; rate limit OTP/password reset.

**Repositories** — Parameterized queries; least-privilege DB user; no `SELECT *`.

**Configuration** — Secrets from env/Vault; HTTPS; CORS allowlist; security headers (CSP, X-Frame-Options, X-Content-Type-Options); actuator: only `/health` public.

## Supply Chain (Java-specific)

- Spring Boot 3.3+: auto-generates CycloneDX SBOMs
- `./gradlew dependencyCheckAnalyze` (OWASP Dep-Check)
- `dependencyManagement` for transitive pinning
- `./gradlew dependencyUpdates` for CVE-flagged libs

## Related

- `rules/java/code-review-core.md` — `CORE-LOG-002` (no sensitive data in logs — password, OTP, full PAN, CVV, JWT)
- `rules/java/code-review-mvc.md` — `MVC-SEC-001` `@PreAuthorize` · `MVC-SEC-002` CSRF · `MVC-SEC-003` rate limit · `MVC-CFG-003` secrets from env/Vault
- `rules/java/code-review-webflux.md` — `WFL-SEC-001` `@EnableWebFluxSecurity` · `WFL-SEC-002` `ReactiveSecurityContextHolder`
- `rules/java/code-review-crosscut.md` — `XCT-DEP-002` CVE scan
- `rules/java/code-review-jackson.md` — `JKS-POL-002` no `Id.CLASS` (RCE — CVE-2017-7525) · `JKS-POL-003` disable default typing · `JKS-ANN-003` password `@JsonIgnore`/`WRITE_ONLY` · `JKS-SEC-003` input size limit · `JKS-SEC-004` mask sensitive on serialize · `JKS-ERR-004` no stack trace leak
- `skills/spring-security` — SecurityWebFilterChain patterns, JWT, CORS
- `skills/summer-security` — APISIX auth, @AuthRoles, Keycloak
- `skills/pentest` — OWASP scanning
