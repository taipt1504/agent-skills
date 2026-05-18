---
name: security-common
description: Language-agnostic security principles — OWASP-aligned, secrets management, supply chain, input validation, secure logging.
globs: "*"
applicability:
  always: true
---

# Security — Language-Agnostic

## Hard Blocks (STOP)

| Violation | Why | Fix |
|---|---|---|
| Hardcoded secrets in source | Git history permanent; attackers scan repos | Env vars / Vault / secret manager |
| String concatenation in SQL | SQL injection (OWASP #3) | Parameterized queries / named params |
| Exposed stack traces in API | Leaks classes, versions, SQL structure | Structured error response (RFC 7807 ProblemDetail) |
| Wildcard CORS in production | CSRF from any origin | Explicit origin allowlist |
| Sensitive data in logs | PII/credentials at aggregator → GDPR breach | Mask PII, no tokens, no full request bodies |
| Unprotected endpoints | OWASP #1 Broken Access Control | Auth + authz everywhere except health |
| Weak password hashing (MD5, SHA-1, bcrypt<10) | Offline brute-force | Argon2id / PBKDF2 high iterations |
| HTTP for any API | Credentials in transit | TLS 1.2+ everywhere |

## Pre-Commit Checklist

- [ ] No hardcoded secrets (API keys, passwords, tokens, DB creds)
- [ ] User inputs validated at boundary
- [ ] Parameterized queries only (no concat)
- [ ] No sensitive data in logs
- [ ] Auth + authz on all endpoints (except health)
- [ ] Errors don't leak internals
- [ ] CORS explicit allowlist
- [ ] Deps scanned for CVEs

## Supply Chain

- SBOM in CI/CD (CycloneDX)
- Dep scanning (OWASP Dep-Check / Snyk)
- Version pinning of transitive deps
- Audit outdated libs with known CVEs

## Response Protocol

1. STOP
2. Assess severity (Critical / Major / Minor)
3. Fix Critical immediately
4. Rotate exposed secrets
5. Scan codebase for similar patterns
6. Reviewer agent for validation

## Related

- `rules/java/security.md` — Spring Security 6.x specifics
- `skills/pentest` — OWASP Top 10 scanning
- `rules/java/observability.md` — security event logging
