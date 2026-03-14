# Security Rules

> This file extends [common/security.md](../common/security.md) with Java specific content.

## Pre-Commit Checklist

- [ ] No hardcoded secrets (API keys, passwords, tokens, DB credentials)
- [ ] All user inputs validated (Bean Validation, custom validators)
- [ ] SQL injection prevention (parameterized queries, no string concat)
- [ ] No sensitive data in logs (PII, credentials, tokens)
- [ ] CSRF protection enabled (Spring Security)
- [ ] Authentication/authorization on all endpoints
- [ ] Rate limiting on public/critical endpoints
- [ ] Error messages don't leak internals (stack traces, SQL errors)
- [ ] Dependencies checked for CVEs (`./gradlew dependencyCheckAnalyze`)

## NEVER / ALWAYS

| Category | NEVER                                               | ALWAYS                                                 |
| -------- | --------------------------------------------------- | ------------------------------------------------------ |
| Secrets  | Hardcode in source or config committed to git       | `@ConfigurationProperties` + env vars / Vault          |
| SQL      | String concatenation in queries                     | `.bind("param", value)` or Spring Data methods         |
| CORS     | Wildcard `*` in production                          | Explicit `setAllowedOrigins(List.of("https://..."))`   |
| Errors   | Expose stack traces, SQL errors, or keys to clients | Generic user-facing message, log full error internally |
| Logging  | Log passwords, tokens, PII, credit cards            | Mask sensitive data, use MDC for tracing context       |
| Auth     | Unprotected endpoints (except health/public)        | `@PreAuthorize` on sensitive methods                   |
| Files    | Accept any upload without validation                | Whitelist extension + MIME type + size limit (5MB)     |

## Security Checklist by Component

### Controllers

- `@Valid` on all request bodies
- No sensitive data in URL parameters
- Proper HTTP methods (GET read-only, POST/PUT/DELETE for mutations)
- `@PreAuthorize` authorization checks

### Services

- Input validation before processing
- No logging of sensitive data
- Transaction boundaries properly defined
- Rate limiting on critical operations

### Repositories

- Parameterized queries only
- No string concatenation in SQL
- Least-privilege database user

### Configuration

- All secrets from environment variables
- HTTPS enforced in production
- CORS explicitly configured
- Security headers set (`X-Frame-Options`, `X-Content-Type-Options`, `HSTS`)

## Security Response Protocol

If security issue found:

1. **STOP** immediately
2. **Use security-reviewer agent** for full analysis
3. **Fix CRITICAL issues** before any other work
4. **Rotate exposed secrets** — new API keys, DB passwords, JWT signing keys
5. **Review codebase** for similar issues
6. **Update dependencies** if CVE found
7. **Document incident** and preventive measures

## Detailed Patterns

For implementation examples and code patterns, see:

- `skills/security-review` — OWASP Top 10, anti-patterns, pre-deployment checklist
- `skills/springboot-security` — JWT filter, SecurityFilterChain, CORS, secrets management
