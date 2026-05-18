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
- NEVER verbs in URLs — use HTTP methods (POST `/api/orders/v1/123/cancel` not POST `/cancelOrder/123`)
- NEVER nest deeper than 2 levels: `/api/orders/v1/{id}/items` (max) — deeper nesting signals missing top-level resource
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

Long-running operations (>5s): return `202 Accepted` with polling URL:
```
POST /api/reports/v1 → 202 Accepted
Location: /api/reports/v1/123/status
```

## Error Responses (RFC 7807)

Enable: `spring.mvc.problemdetail.enabled: true`

- ALWAYS use `ProblemDetail` (Spring 6+) for errors
- ALWAYS include: `type` (URI identifying error class), `title`, `status`, `detail`
- ALWAYS add `errors[]` array for validation failures with `field` and `message`
- NEVER expose stack traces, SQL errors, internal class names, or library versions
- NEVER return `200 OK` with error body — breaks client error handling

## Pagination

- ALWAYS paginate list endpoints — NEVER return unbounded collections (unbounded responses cause OOM)
- ALWAYS cap `size` at 100 — prevents clients requesting millions of rows
- Accept `page` (0-based) and `size` (default 20, max 100)
- Return `Page<T>` with `totalElements`, `totalPages`, `number`, `size`
- PREFER cursor-based pagination for real-time feeds or large datasets (offset-based slows at high offsets)

## Idempotency

Mutation endpoints (POST, PATCH) accept `Idempotency-Key` header for safe retries — prevents duplicate operations on network-failure retries:

- Store processed keys in DB/Redis with TTL (24h)
- Same key + same body → return cached response
- Same key + different body → return `409 Conflict`

## Bulk Operations

- ALWAYS cap bulk at 100 items — unbounded bulk creates unpredictable latency and timeout risks
- Return `207 Multi-Status` for partial success/failure
- Each item includes its own status code

## Validation

- ALWAYS `@Valid @RequestBody` on POST/PUT/PATCH endpoints
- ALWAYS Bean Validation annotations on request DTOs (`@NotBlank`, `@Email`, `@Size`, `@NotNull`, `@Positive`)
- ALWAYS whitelist sort fields — prevent clients injecting arbitrary column names (SQL injection via ORDER BY)
- NEVER expose domain entities directly — use request/response record DTOs
- ALWAYS `@PathVariable` + `@Positive` / `@NotBlank` for path parameters

## Versioning

- ALWAYS version in method path: `/api/orders/v1/...` — version after resource, not before
- Resource mapping version-agnostic: `@RequestMapping("/api/orders")`
- Method paths carry version: `@GetMapping("/v1")`, `@PostMapping("/v2")`
- Maintain backward compatibility within version
- Breaking changes = new version per resource (`v2`) — others stay on `v1`
- Use `Sunset` + `Deprecation` headers when deprecating

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

## OpenAPI / Schema datatype sync (HARD BLOCK)

`@Schema` / `@Operation` / `@ApiResponse` / `@Parameter` MUST stay in sync with Java field datatype + validation. Drift = contract lie → FE codegen wrong → runtime bug.


### Enum

```java
// ❌ DRIFT
@Schema(allowableValues = {"INDIVIDUAL", "ENTERPRISE", "HOUSEHOLD"})
MerchantType merchantType;

// ✅
@Schema(implementation = MerchantType.class)
MerchantType merchantType;
```

### Date/Time

```java
// ❌ LocalDateTime example missing time part
@Schema(type = "string", example = "2026-05-10")
LocalDateTime submittedAt;

// ✅
@Schema(type = "string", format = "date-time", example = "2026-05-10T14:30:00Z")
LocalDateTime submittedAt;
```

### Validation alignment

If `@Min(0)` / `@Max(100)` / `@NotBlank` on field → `@Schema(minimum, maximum, required)` MUST match.

```java
// ❌ DRIFT
@Min(0) @Max(100)
@Schema(description = "Page size")
int size;

// ✅
@Min(0) @Max(100)
@Schema(description = "Page size", minimum = "0", maximum = "100", example = "20")
int size;
```

### Required vs nullable

Record component required by default (Jackson). `@Schema(nullable = true)` only when truly nullable. Mismatch with `@NotNull` / `@NotBlank` → drift.


## DTO typing rule — No `JsonNode` from HTTP clients (HARD BLOCK)

HTTP client methods MUST return strongly-typed Java records. `Mono<JsonNode>` FORBIDDEN.


```java
// ❌ opaque, brittle
public Mono<JsonNode> getLoginHistory(UUID userId, int limit) { ... }
Mono<Boolean> verified = response.map(node -> node.path("verified").asBoolean(false));

// ✅ typed, compile-checked
public Mono<GetLoginHistoryResponse> getLoginHistory(UUID userId, int limit) { ... }
Mono<Boolean> verified = response.map(VerifyStepUpOtpResponse::verified);
```

### DTO requirements

Response DTO records MUST:
1. Be Java record (immutable)
2. `@Schema(description, example)` on non-trivial fields (see OpenAPI section)
3. Mirror server-side field names exactly
4. Javadoc naming originating endpoint

### Generic deserialization

```java
// ❌ type erasure → PageResponse<LinkedHashMap>
.bodyToMono(PageResponse.class)

// ✅ preserves T at runtime
.bodyToMono(new ParameterizedTypeReference<PageResponse<BankAccountHistoryItemResponse>>() {})
```

### Anti-patterns

- `Mono<JsonNode>` return type on client methods
- `node.path("field").asText()` / `.asBoolean()` in handlers
- `Map<String, Object>` substitute
- `JsonNode` field in response record
- `.bodyToMono(JsonNode.class)`

### Exception (rare)

`Mono<JsonNode>` allowed ONLY when ALL three hold:
1. Schema genuinely dynamic (free-form JSON, e.g., webhook payloads from third party)
2. Response passed through as-is (pure proxy, no field access)
3. Documented: `// JsonNode: schema is dynamic — <reason>`

Otherwise → typed record + `@WireMockTest`.

## Related Skills

- **api-design** (skill) — Full cursor/keyset pagination code, filtering, OpenAPI config
- **summer-rest** — Summer Framework handler pattern, ResponseFactory
- **spring-webflux-patterns** — Controller implementation patterns

## Related Rules

- `rules/java/coding-style.md` — DTO typing (records, Lombok)
- `rules/java/testing.md` — `@WireMockTest` for typed client methods
- `rules/summer/handler-api-standards.md` (Summer-only) — SpringBus dispatch, PageResponse
