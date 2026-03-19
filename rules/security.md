---
name: security
description: Security checklist, NEVER/ALWAYS rules, component security, secrets management
globs: "*.java"
---

# Security Rules

## Pre-Commit Checklist

- [ ] No hardcoded secrets (API keys, passwords, tokens, DB credentials)
- [ ] All user inputs validated (Bean Validation, custom validators)
- [ ] SQL injection prevention (parameterized queries, no string concat)
- [ ] No sensitive data in logs (PII, credentials, tokens)
- [ ] CSRF protection enabled; auth/authz on all endpoints
- [ ] Error messages don't leak internals (stack traces, SQL errors)

## NEVER / ALWAYS

| Category | NEVER | ALWAYS |
|----------|-------|--------|
| Secrets | Hardcode in source or committed config | `@ConfigurationProperties` + env vars / Vault |
| SQL | String concatenation in queries | `.bind("param", value)` or Spring Data methods |
| CORS | Wildcard `*` in production | Explicit `setAllowedOrigins(List.of("https://..."))` |
| Errors | Expose stack traces or SQL to clients | Generic user-facing message, log full error internally |
| Logging | Log passwords, tokens, PII, credit cards | Mask sensitive data, use MDC for tracing |
| Auth | Unprotected endpoints (except health) | `@PreAuthorize` on sensitive methods |
| Files | Accept uploads without validation | Whitelist extension + MIME type + size limit |

## Component Security

**Controllers** — `@Valid` on all request bodies, `@PreAuthorize` checks, no sensitive data in URLs.
**Services** — Input validation before processing, no logging of sensitive data, rate limiting on critical ops.
**Repositories** — Parameterized queries only, least-privilege DB user.
**Configuration** — Secrets from env vars, HTTPS enforced, CORS explicit, security headers set.

## Response Protocol

If security issue found: STOP → use reviewer agent → fix CRITICAL issues → rotate exposed secrets → review codebase for similar issues.
