---
name: api-design
description: REST API conventions — URLs, HTTP methods, errors, pagination, validation
globs: "*.java"
---

# API Design Rules

## URL Conventions

- ALWAYS plural nouns: `/api/v1/orders`, `/api/v1/users`
- ALWAYS kebab-case for multi-word: `/api/v1/order-items`
- NEVER verbs in URLs — use HTTP methods instead
- NEVER nested deeper than 2 levels: `/orders/{id}/items` (max)

## HTTP Methods & Status Codes

| Method | Use | Success | Error |
|--------|-----|---------|-------|
| GET | Read | 200 | 404 |
| POST | Create | 201 + Location | 400, 409 |
| PUT | Full replace | 200 | 404, 400 |
| PATCH | Partial update | 200 | 404, 400 |
| DELETE | Remove | 204 (no body) | 404 |

## Error Responses (RFC 7807)

- ALWAYS use `ProblemDetail` (Spring 6+) for error responses
- ALWAYS include: `type`, `title`, `status`, `detail`
- NEVER expose stack traces, SQL errors, or internal class names
- NEVER return `200 OK` with error body

## Pagination

- ALWAYS paginate list endpoints — NEVER return unbounded collections
- Accept `page` (0-based) and `size` (default 20, max 100)
- Return `Page<T>` with `totalElements`, `totalPages`, `number`, `size`
- PREFER cursor-based pagination for real-time or large datasets

## Validation

- ALWAYS `@Valid @RequestBody` on POST/PUT/PATCH endpoints
- ALWAYS Bean Validation annotations on request DTOs
- NEVER expose domain entities directly — use request/response DTOs
- ALWAYS `@PathVariable` + `@Positive` / `@NotBlank` for path params

## Versioning

- PREFER URL path versioning: `/api/v1/orders`
- Maintain backward compatibility within a version; deprecate before removing
