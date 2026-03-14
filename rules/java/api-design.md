# API Design Rules

## URL Conventions

- ALWAYS plural nouns: `/api/v1/orders`, `/api/v1/users`
- ALWAYS kebab-case for multi-word: `/api/v1/order-items`
- NEVER verbs in URLs: `/api/v1/getOrders` — use HTTP methods instead
- NEVER nested deeper than 2 levels: `/orders/{id}/items` (max)

## HTTP Methods & Status Codes

| Method | Use | Success | Error |
|--------|-----|---------|-------|
| GET | Read resource | 200 | 404 |
| POST | Create resource | 201 + Location header | 400, 409 |
| PUT | Full replace | 200 | 404, 400 |
| PATCH | Partial update | 200 | 404, 400 |
| DELETE | Remove resource | 204 (no body) | 404 |

## Error Responses (RFC 7807)

- ALWAYS use `ProblemDetail` (Spring 6+) for error responses
- ALWAYS include: `type`, `title`, `status`, `detail`
- NEVER expose stack traces, SQL errors, or internal class names
- NEVER return `200 OK` with error body — use proper HTTP status codes

## Pagination

- ALWAYS paginate list endpoints — NEVER return unbounded collections
- ALWAYS accept `page` (0-based) and `size` (default 20, max 100)
- ALWAYS return `Page<T>` with `totalElements`, `totalPages`, `number`, `size`
- PREFER cursor-based pagination for real-time data or large datasets

## Validation

- ALWAYS `@Valid @RequestBody` on POST/PUT/PATCH endpoints
- ALWAYS Bean Validation annotations on request DTOs
- NEVER expose domain entities directly — use request/response DTOs
- ALWAYS `@PathVariable` + `@Positive` / `@NotBlank` for path params

## Versioning

- PREFER URL path versioning: `/api/v1/orders`
- ALWAYS maintain backward compatibility within a version
- ALWAYS deprecate before removing (minimum 1 version overlap)

## Detailed Patterns

For code examples and full patterns, see:
- `skills/api-design` — REST conventions, error handling, pagination, content negotiation
- `skills/spring-mvc-patterns` — controller patterns, exception handlers, filters
