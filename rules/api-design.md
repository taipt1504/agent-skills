---
name: api-design
description: REST API design rules — URLs, HTTP methods, RFC 7807 errors, pagination, idempotency, async operations, bulk caps, validation
globs: "*.java"
---

# API Design Rules

## URL Conventions

**Structure**: `Resource Mapping` + `Versioned Path`
- Resource mapping (controller): `/api/${resource}` → `@RequestMapping("/api/orders")`
- Path APIs (method): `/${versioning}/...` → `@GetMapping("/v1")`, `@GetMapping("/v1/{id}")`
- Full URL: `/api/${resource}/${versioning}/...` → `/api/orders/v1`, `/api/orders/v1/{id}`

**Rules:**
- ALWAYS plural nouns: `/api/orders`, `/api/users`
- ALWAYS kebab-case for multi-word: `/api/order-items`
- NEVER verbs in URLs — use HTTP methods instead (POST `/api/orders/v1/123/cancel` not POST `/cancelOrder/123`)
- NEVER nested deeper than 2 levels: `/api/orders/v1/{id}/items` (max) — deeper nesting signals a missing top-level resource
- Version belongs to method path, NOT resource mapping — enables per-resource version bumps

## HTTP Methods & Status Codes

| Method | Use | Idempotent | Success | Error |
|--------|-----|------------|---------|-------|
| GET | Read | Yes | 200 | 404 |
| POST | Create | No | 201 + `Location` header | 400, 409 |
| PUT | Full replace | Yes | 200 | 404, 400 |
| PATCH | Partial update | No | 200 | 404, 400 |
| DELETE | Remove | Yes | 204 (no body) | 404 |

### Async Operations

For long-running operations (>5s), return `202 Accepted` with a polling URL:
```
POST /api/reports/v1 → 202 Accepted
Location: /api/reports/v1/123/status
```

## Error Responses (RFC 7807)

Enable: `spring.mvc.problemdetail.enabled: true`

- ALWAYS use `ProblemDetail` (Spring 6+) for error responses — this is the standard
- ALWAYS include: `type` (URI identifying the error class), `title`, `status`, `detail`
- ALWAYS add `errors[]` array for validation failures with `field` and `message`
- NEVER expose stack traces, SQL errors, internal class names, or library versions
- NEVER return `200 OK` with error body — this breaks client error handling

## Pagination

- ALWAYS paginate list endpoints — NEVER return unbounded collections (unbounded responses cause OOM under load)
- ALWAYS cap `size` at 100 — prevent clients requesting millions of rows
- Accept `page` (0-based) and `size` (default 20, max 100)
- Return `Page<T>` with `totalElements`, `totalPages`, `number`, `size`
- PREFER cursor-based pagination for real-time feeds or large datasets (offset-based pagination becomes slow at high offsets)

## Idempotency

Mutation endpoints (POST, PATCH) should accept an `Idempotency-Key` header for safe retries. This prevents duplicate operations when clients retry after network failures:

- Store processed keys in DB/Redis with TTL (24h typical)
- Same key + same request body → return cached response
- Same key + different body → return `409 Conflict`

## Bulk Operations

- ALWAYS cap bulk operations at 100 items per request — unbounded bulk creates unpredictable latency and timeout risks
- Return `207 Multi-Status` for partial success/failure
- Each item in the response includes its own status code

## Validation

- ALWAYS `@Valid @RequestBody` on POST/PUT/PATCH endpoints
- ALWAYS Bean Validation annotations on request DTOs (`@NotBlank`, `@Email`, `@Size`, `@NotNull`, `@Positive`)
- ALWAYS whitelist sort fields — prevent clients injecting arbitrary column names (SQL injection via ORDER BY)
- NEVER expose domain entities directly — use request/response record DTOs
- ALWAYS `@PathVariable` + `@Positive` / `@NotBlank` for path parameters

## Versioning

- ALWAYS version in method path: `/api/orders/v1/...` — version after resource, not before
- Resource mapping is version-agnostic: `@RequestMapping("/api/orders")`
- Method paths carry the version: `@GetMapping("/v1")`, `@PostMapping("/v2")`
- Maintain backward compatibility within a version
- Breaking changes = new version per resource (`v2`) — other resources stay on `v1`
- Use `Sunset` + `Deprecation` headers when deprecating a version

## Checklist

- [ ] Plural nouns, kebab-case, max 2-level nesting
- [ ] Correct HTTP methods and status codes
- [ ] RFC 7807 `ProblemDetail` for all errors
- [ ] `@Valid` on all `@RequestBody`
- [ ] `Location` header on 201 responses
- [ ] Pagination with max size cap (100) on all list endpoints
- [ ] Sort field whitelist
- [ ] Idempotency keys on mutation endpoints
- [ ] Bulk operations capped at 100
- [ ] Async ops use 202 + polling
- [ ] OpenAPI docs (`@Operation`, `@ApiResponse`)
- [ ] Rate limiting headers (`X-RateLimit-Limit/Remaining/Reset`)

## Related Skills

- **api-design** (skill) — Full cursor/keyset pagination code, filtering, OpenAPI config
- **summer-rest** — Summer Framework handler pattern, ResponseFactory
- **spring-patterns** — Controller implementation patterns
