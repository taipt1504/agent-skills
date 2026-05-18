---
name: api-design
description: >
  REST API design patterns for Spring Boot — HTTP methods, status codes, URL conventions,
  RFC 7807 ProblemDetail errors, pagination, versioning, validation, and OpenAPI documentation.
  Use when designing REST endpoints, choosing HTTP status codes, implementing error responses,
  adding pagination to list APIs, versioning APIs, or generating OpenAPI/Swagger specs.
triggers:
  natural: ["api design", "error format", "pagination design", "openapi", "rest conventions"]
  code: ["RFC 7807", "ProblemDetail", "OpenAPI", "Pageable"]
applicability:
  always: false
  triggers:
    files_match: ["**/*Controller.java", "**/*Handler.java", "**/*RouterFunction*.java", "**/openapi*.yml", "**/openapi*.yaml"]
    code_patterns: ["@RestController", "@RequestMapping", "ResponseEntity", "ProblemDetail", "@Operation", "@ApiResponse"]
    task_keywords: ["endpoint", "REST", "API", "OpenAPI", "Swagger", "ProblemDetail", "pagination design", "HTTP status"]
    related_rules:
      - rules/java/api-design.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 80%+: new endpoint OR contract change OR OpenAPI annotations
  MEDIUM 40-79%: existing endpoint behavior tweak, no contract change
  LOW 1-39%: caller refactor without endpoint touch
  ZERO: no REST surface in scope (verify: grep -r '@RestController' src/main/ = 0)
---

# REST API Design Patterns

## HTTP Methods & Status Codes

| Method | Purpose | Idempotent | Success Code |
|--------|---------|------------|--------------|
| `GET` | Read | Yes | 200 |
| `POST` | Create | No | 201 + Location |
| `PUT` | Full replace | Yes | 200 |
| `PATCH` | Partial update | No | 200 |
| `DELETE` | Remove | Yes | 204 |

Key codes: 201 (Created + Location), 202 (Async), 204 (No content), 400 (Validation), 401 (Unauthenticated), 403 (Forbidden), 404 (Not found), 409 (Conflict), 422 (Semantic), 429 (Rate limited).

## URL Conventions

- **Resource mapping** (controller): `/api/${resource}`
- **Path APIs** (method): `/${versioning}/...`
- **Full URL**: `/api/${resource}/${versioning}/...`

```
# Controller: @RequestMapping("/api/users")
GET    /api/users/v1               # List
POST   /api/users/v1               # Create
GET    /api/users/v1/123           # Get by ID
PUT    /api/users/v1/123           # Replace
DELETE /api/users/v1/123           # Delete
GET    /api/users/v1/123/orders    # Nested (max 2 levels)

# Controller: @RequestMapping("/api/orders")
POST   /api/orders/v1/123/cancel   # Action as sub-resource
```

Rules: plural nouns, kebab-case, lowercase, no trailing slash, no verbs. Version on method, NOT resource mapping — enables per-resource bumps.

## Error Format — RFC 7807

```json
{
  "type": "https://api.example.com/problems/validation-error",
  "title": "Validation Error",
  "status": 400,
  "detail": "Request validation failed",
  "errors": [{"field": "email", "message": "must be a valid email"}]
}
```

Enable: `spring.mvc.problemdetail.enabled: true`. Use `@RestControllerAdvice` with `ProblemDetail`.

## Pagination

| Type | Best For | Notes |
|------|----------|-------|
| Offset (`page=0&size=20`) | Admin UIs | Simple; slow at large offsets |
| Cursor (opaque token) | Feeds, infinite scroll | Consistent; no drift |
| Keyset (`afterId=X`) | Large datasets | Fastest; needs composite index |

Cap `size` at 100. Prefer cursor/keyset.

## Versioning

Version in method path: `/api/{resource}/{version}/...`. v1 is forever — backward compatible. Optional fields for minor changes. Breaking changes = new version. Use `Sunset` + `Deprecation` headers.

## Validation & Rate Limiting

- `@Valid` on all `@RequestBody`. Bean Validation: `@NotBlank`, `@Email`, `@Size`, `@NotNull`.
- Whitelist sort fields to prevent injection.
- Rate limit headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After`.

## Checklist

- [ ] Plural nouns, kebab-case, max 2-level nesting
- [ ] Correct HTTP methods and status codes
- [ ] RFC 7807 Problem Details for errors
- [ ] `@Valid` on all `@RequestBody`
- [ ] Global `@RestControllerAdvice` exception handler
- [ ] Pagination on list endpoints (cursor preferred)
- [ ] Sort field whitelist
- [ ] API version in URL path
- [ ] `Location` header on 201 responses
- [ ] Rate limiting with standard headers
- [ ] OpenAPI docs (`@Operation`, `@ApiResponse`)
- [ ] Idempotency keys on mutation endpoints
- [ ] Bulk operations capped (max 100)
- [ ] Async ops use 202 + polling

## References

- **[references/design-patterns.md](references/design-patterns.md)** — Cursor/keyset pagination code, filtering/sorting, field selection, OpenAPI config
- **[references/operations-docs.md](references/operations-docs.md)** — File upload/download, idempotency, bulk operations, long-running operations

## Related Skills

- **summer-rest** — Summer Framework handler pattern, ResponseFactory, exception handling
- **spring-webflux-patterns** — Controller implementation patterns (MVC + WebFlux)
- **spring-security** — Rate limiting headers, CORS, authentication for APIs
- **architecture** — Hexagonal interface layer design for REST endpoints
