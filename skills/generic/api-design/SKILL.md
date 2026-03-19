---
name: api-design
description: >
  REST API design patterns for Spring Boot WebFlux — HTTP methods, status codes, URL conventions,
  RFC 7807 errors, pagination, versioning, validation, rate limiting, and OpenAPI documentation.
triggers:
  - REST endpoints
  - DTO design
  - pagination
  - error format
  - API versioning
  - OpenAPI
  - rate limiting headers
---

# REST API Design Patterns

Production-ready API design for Java 17+ / Spring Boot 3.x / WebFlux.

## HTTP Methods & Status Codes

| Method | Purpose | Idempotent | Success Code |
|--------|---------|------------|--------------|
| `GET` | Read | Yes | 200 |
| `POST` | Create | No | 201 + Location |
| `PUT` | Full replace | Yes | 200 |
| `PATCH` | Partial update | No | 200 |
| `DELETE` | Remove | Yes | 204 |

Key status codes: 201 (Created + Location), 202 (Async accepted), 204 (No content), 400 (Validation), 401 (Unauthenticated), 403 (Forbidden), 404 (Not found), 409 (Conflict), 422 (Semantic error), 429 (Rate limited).

## URL Conventions

```
GET    /api/v1/users              # List
POST   /api/v1/users              # Create
GET    /api/v1/users/123          # Get by ID
PUT    /api/v1/users/123          # Replace
DELETE /api/v1/users/123          # Delete
GET    /api/v1/users/123/orders   # Nested (max 2 levels)
POST   /api/v1/orders/123/cancel  # Action as sub-resource
```

Rules: plural nouns, kebab-case, lowercase, no trailing slash, no verbs in path.

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

Enable: `spring.mvc.problemdetail.enabled: true`. Use `@RestControllerAdvice` with `ProblemDetail` responses.

## Pagination

| Type | Best For | Notes |
|------|----------|-------|
| Offset (`page=0&size=20`) | Admin UIs | Simple; slow at large offsets |
| Cursor (opaque token) | Feeds, infinite scroll | Consistent; no drift |
| Keyset (`afterId=X`) | Large datasets | Fastest; needs composite index |

Always cap `size` at 100. Prefer cursor/keyset for APIs.

## Versioning

URI path: `/api/v1/...`. v1 is forever — backward compatible. Add optional fields for minor changes. Breaking changes = new version. Use `Sunset` + `Deprecation` headers.

## Validation & Rate Limiting

- `@Valid` on all `@RequestBody`. Bean Validation: `@NotBlank`, `@Email`, `@Size`, `@NotNull`.
- Sort field whitelist to prevent injection.
- Rate limiting headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After`.

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

- **[references/design-patterns.md](references/design-patterns.md)** — Cursor/keyset pagination code, filtering/sorting, field selection, content negotiation, HATEOAS, OpenAPI config
- **[references/operations-docs.md](references/operations-docs.md)** — File upload/download, idempotency, bulk operations, long-running operations, contract testing (Spring Cloud Contract + Pact)
