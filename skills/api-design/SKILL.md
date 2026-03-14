---
name: api-design
description: >
  REST API design patterns and versioning for Spring Boot WebFlux applications.
  Covers RESTful principles, URL conventions, DTOs, error format (RFC 7807),
  pagination (offset/cursor/keyset), filtering, sorting, API versioning,
  rate limiting, OpenAPI documentation, validation, exception handling,
  idempotency, bulk operations, long-running operations, file upload/download,
  and contract testing. Use when designing or reviewing REST APIs with
  Spring Boot 3.x, WebFlux, and Java 17+.
---

# REST API Design Patterns

Production-ready API design for Java 17+ / Spring Boot 3.x / WebFlux.

## HTTP Methods & Status Codes

| Method | Purpose | Idempotent | Success Code |
|--------|---------|------------|--------------|
| `GET` | Read resource | ✅ | 200 |
| `POST` | Create resource | ❌ | 201 + Location header |
| `PUT` | Full replace | ✅ | 200 |
| `PATCH` | Partial update | ❌ | 200 |
| `DELETE` | Remove | ✅ | 204 |

| Code | When |
|------|------|
| `201 Created` | POST — include `Location` header |
| `202 Accepted` | Async operation accepted |
| `204 No Content` | DELETE, PUT with no response body |
| `400 Bad Request` | Validation error |
| `401 Unauthorized` | Authentication required |
| `403 Forbidden` | Authenticated but not authorized |
| `404 Not Found` | Resource missing |
| `409 Conflict` | Duplicate, optimistic lock |
| `422 Unprocessable` | Semantic validation error |
| `429 Too Many Requests` | Rate limited |

---

## URL Conventions

```
GET    /api/v1/users              # List
GET    /api/v1/users/123          # Get by ID
POST   /api/v1/users              # Create
PUT    /api/v1/users/123          # Replace
PATCH  /api/v1/users/123          # Update
DELETE /api/v1/users/123          # Delete
GET    /api/v1/users/123/orders   # Nested resource (max 2 levels)
POST   /api/v1/orders/123/cancel  # Action as sub-resource
```

Rules: plural nouns, kebab-case, lowercase, no trailing slash, no verbs in path.

---

## Request/Response

```java
// Request DTO — validate with Bean Validation
public record CreateUserRequest(
    @NotBlank @Email String email,
    @NotBlank @Size(min = 2, max = 100) String name,
    @NotNull UserRole role
) {}

// Response DTO — expose only what's needed
public record UserResponse(Long id, String email, String name, UserRole role,
                           boolean active, Instant createdAt) {}
```

### Error Format — RFC 7807

```json
{
  "type": "https://api.example.com/problems/validation-error",
  "title": "Validation Error",
  "status": 400,
  "detail": "Request validation failed",
  "instance": "/api/v1/users",
  "errors": [{"field": "email", "message": "must be a valid email"}]
}
```

Spring Boot 3.x: `spring.mvc.problemdetail.enabled: true` — auto-maps `ResponseStatusException` to Problem Details.

---

## Pagination Types

| Type | Best For | Notes |
|------|----------|-------|
| Offset (`page=0&size=20`) | Admin UIs, small data | Simple; O(N) at large offsets |
| Cursor (opaque token) | Infinite scroll, feeds | Consistent; no drift |
| Keyset (`afterId=X&afterCreatedAt=Y`) | Large datasets | Fastest; requires composite index |

**Recommendation:** Use cursor/keyset for APIs. Always cap `size` at 100.

---

## API Versioning

**Recommendation: URI path versioning** — `/api/v1/...`

```java
@RestController @RequestMapping("/api/v1/users")
public class UserControllerV1 { ... }

@RestController @RequestMapping("/api/v2/users")
public class UserControllerV2 { ... }
```

Rules:
- v1 is forever — maintain backward compatibility
- Minor changes: add optional fields only
- Breaking changes: new version (v2)
- Use `Sunset` + `Deprecation` headers when deprecating

---

## Exception Handling

```java
@RestControllerAdvice @Slf4j
public class GlobalExceptionHandler {
    @ExceptionHandler(WebExchangeBindException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ProblemDetail handleValidation(WebExchangeBindException ex, ServerWebExchange exchange) {
        var problem = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST);
        problem.setTitle("Validation Error");
        problem.setProperty("errors", ex.getFieldErrors().stream()
            .map(e -> Map.of("field", e.getField(), "message", e.getDefaultMessage())).toList());
        return problem;
    }

    @ExceptionHandler(NotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ProblemDetail handleNotFound(NotFoundException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ProblemDetail handleAll(Exception ex) {
        log.error("Unhandled exception", ex);
        return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR,
            "An unexpected error occurred");  // ← never expose internal details
    }
}
```

---

## Rate Limiting Headers

```
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1703280000
Retry-After: 60
```

---

## Checklist

- [ ] Resources plural nouns, kebab-case, max 2-level nesting
- [ ] Correct HTTP methods and status codes
- [ ] RFC 7807 Problem Details for all errors
- [ ] `@Valid` on all `@RequestBody` parameters
- [ ] Global `@RestControllerAdvice` exception handler
- [ ] Pagination on all list endpoints (cursor preferred)
- [ ] Sort field whitelist (prevent injection)
- [ ] API version in URL path (`/api/v1/...`)
- [ ] `Location` header on 201 responses
- [ ] Rate limiting with standard headers
- [ ] OpenAPI docs (`@Operation`, `@ApiResponse`)
- [ ] Idempotency keys on mutation endpoints
- [ ] Bulk operations capped (max 100 items)
- [ ] Async operations use 202 + polling pattern

---

## References

Load as needed:

- **[references/design-patterns.md](references/design-patterns.md)** — Detailed pagination (cursor, keyset code), filtering/sorting, field selection, content negotiation, HATEOAS, OpenAPI config
- **[references/operations-docs.md](references/operations-docs.md)** — File upload/download, idempotency, bulk operations, long-running operations, contract testing (Spring Cloud Contract + Pact)
