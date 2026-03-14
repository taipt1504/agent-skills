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
version: 1.0.0
---

# REST API Design Patterns

Production-ready API design patterns for Java 17+ / Spring Boot 3.x / WebFlux.

## Quick Reference

| Category | When to Use | Jump To |
|----------|------------|---------|
| RESTful Principles | Designing resources | [RESTful Principles](#restful-design-principles) |
| URL Structure | Naming endpoints | [URL Structure](#url-structure-conventions) |
| Request/Response | DTOs, envelopes, errors | [Request/Response](#requestresponse-patterns) |
| Pagination | Listing resources | [Pagination](#pagination) |
| Filtering & Sorting | Query capabilities | [Filtering & Sorting](#filtering-sorting-field-selection) |
| Versioning | API evolution | [Versioning](#api-versioning) |
| Rate Limiting | Throttling | [Rate Limiting](#rate-limiting) |
| OpenAPI | Documentation | [OpenAPI](#openapi-documentation) |
| Validation | Input validation | [Validation](#input-validation) |
| Exception Handling | Error responses | [Exception Handling](#exception-handling) |
| Content Negotiation | Multiple formats | [Content Negotiation](#content-negotiation) |
| File Operations | Upload/download | [File Operations](#file-upload--download) |
| Idempotency | Safe retries | [Idempotency](#idempotency) |
| Bulk Operations | Batch processing | [Bulk Operations](#bulk-operations) |
| Long-Running Ops | Async operations | [Long-Running Operations](#long-running-operations) |
| Router Functions | WebFlux style | [Router Functions](#webflux-router-functions) |
| Contract Testing | API contracts | [Contract Testing](#contract-testing) |

---

## Dependencies

```xml
<!-- Spring WebFlux -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webflux</artifactId>
</dependency>

<!-- Bean Validation -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-validation</artifactId>
</dependency>

<!-- OpenAPI / Swagger -->
<dependency>
    <groupId>org.springdoc</groupId>
    <artifactId>springdoc-openapi-starter-webflux-ui</artifactId>
    <version>2.5.0</version>
</dependency>

<!-- Spring Cloud Contract (testing) -->
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-contract-verifier</artifactId>
    <scope>test</scope>
</dependency>
```

---

## RESTful Design Principles

### HTTP Methods

| Method | Purpose | Idempotent | Safe | Request Body | Success Code |
|--------|---------|------------|------|-------------|--------------|
| `GET` | Read resource(s) | ✅ | ✅ | No | 200 |
| `POST` | Create resource | ❌ | ❌ | Yes | 201 |
| `PUT` | Full replace | ✅ | ❌ | Yes | 200 |
| `PATCH` | Partial update | ❌* | ❌ | Yes | 200 |
| `DELETE` | Remove resource | ✅ | ❌ | No† | 204 |
| `HEAD` | Check existence | ✅ | ✅ | No | 200 |
| `OPTIONS` | Describe capabilities | ✅ | ✅ | No | 200/204 |

*PATCH can be made idempotent with JSON Merge Patch.
†DELETE may accept body for batch delete, but prefer query params.

### Status Codes — When to Use

| Range | Code | When |
|-------|------|------|
| **2xx** | `200 OK` | Successful GET, PUT, PATCH |
| | `201 Created` | Successful POST (include Location header) |
| | `202 Accepted` | Async operation accepted |
| | `204 No Content` | Successful DELETE, or PUT with no body |
| **3xx** | `301 Moved Permanently` | Resource moved (update bookmarks) |
| | `304 Not Modified` | Conditional GET, cache valid |
| **4xx** | `400 Bad Request` | Validation error, malformed request |
| | `401 Unauthorized` | Authentication required |
| | `403 Forbidden` | Authenticated but not authorized |
| | `404 Not Found` | Resource not found |
| | `405 Method Not Allowed` | Wrong HTTP method |
| | `409 Conflict` | Duplicate, optimistic lock conflict |
| | `415 Unsupported Media Type` | Wrong Content-Type |
| | `422 Unprocessable Entity` | Semantic validation error |
| | `429 Too Many Requests` | Rate limited |
| **5xx** | `500 Internal Server Error` | Unexpected server error |
| | `502 Bad Gateway` | Downstream service error |
| | `503 Service Unavailable` | Temporarily unavailable |
| | `504 Gateway Timeout` | Downstream timeout |

---

## URL Structure Conventions

### Resource Naming

```
✅ GOOD:
GET    /api/v1/users                  # List users
GET    /api/v1/users/123              # Get user by ID
POST   /api/v1/users                  # Create user
PUT    /api/v1/users/123              # Replace user
PATCH  /api/v1/users/123              # Update user
DELETE /api/v1/users/123              # Delete user

GET    /api/v1/users/123/orders       # User's orders (nested resource)
GET    /api/v1/orders/456             # Direct access to order
POST   /api/v1/users/123/orders       # Create order for user

❌ BAD:
GET    /api/v1/getUser/123            # Verbs in URL
GET    /api/v1/user/123               # Singular (use plural)
POST   /api/v1/users/create           # Verb suffix
GET    /api/v1/users/123/orders/456/items/789  # Too deep nesting (max 2 levels)
```

### Naming Rules

| Rule | Example |
|------|---------|
| Plural nouns | `/users`, `/orders`, `/products` |
| Kebab-case for multi-word | `/order-items`, `/payment-methods` |
| No trailing slash | `/users` not `/users/` |
| Lowercase | `/api/v1/users` not `/Api/V1/Users` |
| Max 2 levels nesting | `/users/123/orders` ✅, avoid deeper |
| Actions as sub-resource | `POST /orders/123/cancel` for non-CRUD ops |

### Query Parameters

```
# Pagination
GET /api/v1/users?page=0&size=20

# Filtering
GET /api/v1/users?status=active&role=admin

# Sorting
GET /api/v1/users?sort=name,asc&sort=createdAt,desc

# Field selection (sparse fieldsets)
GET /api/v1/users?fields=id,name,email

# Search
GET /api/v1/users?q=john

# Combining
GET /api/v1/users?status=active&sort=name,asc&page=0&size=20&fields=id,name
```

---

## Request/Response Patterns

### DTOs — Records (Java 17+)

```java
// Request DTOs — validate input
public record CreateUserRequest(
    @NotBlank @Email String email,
    @NotBlank @Size(min = 2, max = 100) String name,
    @NotNull UserRole role
) {}

public record UpdateUserRequest(
    @Email String email,
    @Size(min = 2, max = 100) String name,
    UserRole role
) {}

// Response DTO — expose only what's needed
public record UserResponse(
    Long id,
    String email,
    String name,
    UserRole role,
    boolean active,
    Instant createdAt,
    Instant updatedAt
) {
    // Factory method from entity
    public static UserResponse from(UserEntity entity) {
        return new UserResponse(
            entity.getId(),
            entity.getEmail(),
            entity.getName(),
            entity.getRole(),
            entity.isActive(),
            entity.getCreatedAt(),
            entity.getUpdatedAt()
        );
    }
}
```

### Response Envelope — PagedResponse

```java
// Generic paged response
public record PagedResponse<T>(
    List<T> content,
    PageInfo page
) {
    public record PageInfo(
        int number,
        int size,
        long totalElements,
        int totalPages,
        boolean first,
        boolean last
    ) {}

    public static <T> PagedResponse<T> of(List<T> content, int page, int size, long total) {
        int totalPages = (int) Math.ceil((double) total / size);
        return new PagedResponse<>(
            content,
            new PageInfo(page, size, total, totalPages, page == 0, page >= totalPages - 1)
        );
    }
}

// Cursor-based response
public record CursorResponse<T>(
    List<T> content,
    CursorInfo cursor
) {
    public record CursorInfo(
        String next,
        boolean hasMore
    ) {}

    public static <T> CursorResponse<T> of(List<T> content, String nextCursor, boolean hasMore) {
        return new CursorResponse<>(content, new CursorInfo(nextCursor, hasMore));
    }
}
```

### Error Format — RFC 7807 Problem Details

```java
// Spring Boot 3.x has built-in ProblemDetail support
// application.yml
// spring.mvc.problemdetail.enabled: true  (for MVC)
// For WebFlux, use custom exception handler

public record ProblemDetailResponse(
    String type,           // URI reference for error type
    String title,          // Human-readable summary
    int status,            // HTTP status code
    String detail,         // Human-readable explanation
    String instance,       // URI of the specific occurrence
    Map<String, Object> extensions  // Additional fields
) {
    // Standard factory methods
    public static ProblemDetailResponse notFound(String detail, String instance) {
        return new ProblemDetailResponse(
            "https://api.example.com/problems/not-found",
            "Not Found",
            404,
            detail,
            instance,
            null
        );
    }

    public static ProblemDetailResponse validationError(
            String detail, String instance, List<FieldError> errors) {
        return new ProblemDetailResponse(
            "https://api.example.com/problems/validation-error",
            "Validation Error",
            400,
            detail,
            instance,
            Map.of("errors", errors)
        );
    }
}

// Field-level errors
public record FieldError(
    String field,
    String message,
    Object rejectedValue
) {}
```

Example error response:
```json
{
  "type": "https://api.example.com/problems/validation-error",
  "title": "Validation Error",
  "status": 400,
  "detail": "Request validation failed",
  "instance": "/api/v1/users",
  "errors": [
    {
      "field": "email",
      "message": "must be a well-formed email address",
      "rejectedValue": "not-an-email"
    },
    {
      "field": "name",
      "message": "must not be blank",
      "rejectedValue": ""
    }
  ]
}
```

---

## Pagination

### Offset-Based Pagination

```java
// Simple but has issues with large offsets (DB scans)
@GetMapping("/users")
public Mono<PagedResponse<UserResponse>> listUsers(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size) {

    size = Math.min(size, 100); // cap page size

    return Mono.zip(
        userRepository.findAllBy(PageRequest.of(page, size))
            .map(UserResponse::from)
            .collectList(),
        userRepository.count()
    ).map(tuple -> PagedResponse.of(tuple.getT1(), page, size, tuple.getT2()));
}
```

### Cursor-Based Pagination (Recommended)

```java
// More efficient than offset — no skip/scan
@GetMapping("/users")
public Mono<CursorResponse<UserResponse>> listUsers(
        @RequestParam(defaultValue = "20") int size,
        @RequestParam(required = false) String cursor) {

    size = Math.min(size, 100);

    Mono<List<UserResponse>> usersMono;
    if (cursor != null) {
        Long cursorId = decodeCursor(cursor);
        usersMono = userRepository
            .findByIdGreaterThanOrderByIdAsc(cursorId, PageRequest.of(0, size + 1))
            .map(UserResponse::from)
            .collectList();
    } else {
        usersMono = userRepository
            .findAllByOrderByIdAsc(PageRequest.of(0, size + 1))
            .map(UserResponse::from)
            .collectList();
    }

    return usersMono.map(users -> {
        boolean hasMore = users.size() > size;
        var content = hasMore ? users.subList(0, size) : users;
        String nextCursor = hasMore ? encodeCursor(content.getLast().id()) : null;
        return CursorResponse.of(content, nextCursor, hasMore);
    });
}

// Cursor encoding/decoding (Base64 for simplicity)
private String encodeCursor(Long id) {
    return Base64.getUrlEncoder().encodeToString(String.valueOf(id).getBytes());
}

private Long decodeCursor(String cursor) {
    return Long.parseLong(new String(Base64.getUrlDecoder().decode(cursor)));
}
```

### Keyset Pagination (Best Performance)

```java
// Best for large datasets — uses WHERE clause instead of OFFSET
@GetMapping("/users")
public Mono<CursorResponse<UserResponse>> listUsersKeyset(
        @RequestParam(defaultValue = "20") int size,
        @RequestParam(required = false) Instant afterCreatedAt,
        @RequestParam(required = false) Long afterId) {

    size = Math.min(size, 100);

    Flux<UserEntity> usersFlux;
    if (afterCreatedAt != null && afterId != null) {
        // Keyset: WHERE (created_at, id) > (:afterCreatedAt, :afterId)
        usersFlux = userRepository.findByKeysetAfter(afterCreatedAt, afterId, size + 1);
    } else {
        usersFlux = userRepository.findFirstPage(size + 1);
    }

    return usersFlux.map(UserResponse::from)
        .collectList()
        .map(users -> {
            boolean hasMore = users.size() > size;
            var content = hasMore ? users.subList(0, size) : users;
            String nextCursor = hasMore
                ? encodeKeysetCursor(content.getLast())
                : null;
            return CursorResponse.of(content, nextCursor, hasMore);
        });
}

// Repository
public interface UserRepository extends ReactiveCrudRepository<UserEntity, Long> {

    @Query("""
        SELECT * FROM users
        WHERE (created_at, id) > (:afterCreatedAt, :afterId)
        ORDER BY created_at ASC, id ASC
        LIMIT :limit
        """)
    Flux<UserEntity> findByKeysetAfter(Instant afterCreatedAt, Long afterId, int limit);

    @Query("SELECT * FROM users ORDER BY created_at ASC, id ASC LIMIT :limit")
    Flux<UserEntity> findFirstPage(int limit);
}
```

### Pagination Comparison

| Strategy | Large Offsets | Consistency | Complexity | Best For |
|----------|--------------|-------------|------------|----------|
| Offset | ❌ Slow (O(n)) | ❌ Page drift | Low | Admin UIs, small datasets |
| Cursor | ✅ Fast (O(1)) | ✅ Consistent | Medium | APIs, infinite scroll |
| Keyset | ✅ Fastest | ✅ Consistent | Medium | Large datasets, feeds |

---

## Filtering, Sorting, Field Selection

### Filtering

```java
// Query parameter approach
@GetMapping("/users")
public Flux<UserResponse> search(
        @RequestParam(required = false) String status,
        @RequestParam(required = false) String role,
        @RequestParam(required = false) String email,
        @RequestParam(required = false) Instant createdAfter,
        @RequestParam(required = false) Instant createdBefore) {

    var criteria = UserSearchCriteria.builder()
        .status(status)
        .role(role)
        .email(email)
        .createdAfter(createdAfter)
        .createdBefore(createdBefore)
        .build();

    return userService.search(criteria).map(UserResponse::from);
}

// Dynamic query building
@Repository
@RequiredArgsConstructor
public class UserSearchRepository {

    private final DatabaseClient db;

    public Flux<UserEntity> search(UserSearchCriteria criteria) {
        var sql = new StringBuilder("SELECT * FROM users WHERE 1=1");
        var params = new HashMap<String, Object>();

        if (criteria.status() != null) {
            sql.append(" AND status = :status");
            params.put("status", criteria.status());
        }
        if (criteria.role() != null) {
            sql.append(" AND role = :role");
            params.put("role", criteria.role());
        }
        if (criteria.email() != null) {
            sql.append(" AND email ILIKE :email");
            params.put("email", "%" + criteria.email() + "%");
        }
        if (criteria.createdAfter() != null) {
            sql.append(" AND created_at >= :createdAfter");
            params.put("createdAfter", criteria.createdAfter());
        }

        var spec = db.sql(sql.toString());
        for (var entry : params.entrySet()) {
            spec = spec.bind(entry.getKey(), entry.getValue());
        }

        return spec.map(this::mapRow).all();
    }
}
```

### Sorting

```java
// Parse sort parameter: sort=name,asc&sort=createdAt,desc
@GetMapping("/users")
public Flux<UserResponse> listSorted(@RequestParam(required = false) List<String> sort) {
    var orderBy = parseSortParams(sort);
    return userService.findAll(orderBy).map(UserResponse::from);
}

private List<SortField> parseSortParams(List<String> sort) {
    if (sort == null || sort.isEmpty()) {
        return List.of(new SortField("createdAt", SortDirection.DESC));
    }

    // Whitelist allowed sort fields to prevent SQL injection
    var allowedFields = Set.of("name", "email", "createdAt", "updatedAt", "role");

    return sort.stream()
        .map(s -> {
            var parts = s.split(",");
            String field = parts[0];
            if (!allowedFields.contains(field)) {
                throw new BadRequestException("Invalid sort field: " + field);
            }
            var direction = parts.length > 1 && "desc".equalsIgnoreCase(parts[1])
                ? SortDirection.DESC : SortDirection.ASC;
            return new SortField(field, direction);
        })
        .toList();
}
```

### Field Selection (Sparse Fieldsets)

```java
// GET /api/v1/users?fields=id,name,email
@GetMapping("/users")
public Flux<Map<String, Object>> listWithFields(
        @RequestParam(required = false) Set<String> fields) {

    if (fields == null || fields.isEmpty()) {
        return userService.findAll().map(this::toFullMap);
    }

    // Whitelist allowed fields
    var allowed = Set.of("id", "name", "email", "role", "active", "createdAt");
    var requestedFields = fields.stream()
        .filter(allowed::contains)
        .collect(Collectors.toSet());
    requestedFields.add("id"); // always include ID

    return userService.findAll()
        .map(user -> filterFields(toFullMap(user), requestedFields));
}

private Map<String, Object> filterFields(Map<String, Object> full, Set<String> fields) {
    return full.entrySet().stream()
        .filter(e -> fields.contains(e.getKey()))
        .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
}
```

---

## API Versioning

### Strategy Comparison

| Strategy | URL | Headers | Pros | Cons |
|----------|-----|---------|------|------|
| URI Path | `/api/v1/users` | None | Simple, visible, cacheable | URL changes |
| Custom Header | `/api/users` | `Api-Version: 1` | Clean URLs | Hidden, harder to test |
| Accept Header | `/api/users` | `Accept: application/vnd.api.v1+json` | RESTful | Complex, harder to test |
| Query Param | `/api/users?version=1` | None | Flexible | Not RESTful, cache issues |

**Recommendation**: Use **URI path versioning** (`/api/v1/...`) — most widely adopted, easiest to understand, route, cache, and test.

### URI Path Versioning (Recommended)

```java
// Version 1
@RestController
@RequestMapping("/api/v1/users")
public class UserControllerV1 {

    @GetMapping("/{id}")
    public Mono<UserResponseV1> getUser(@PathVariable Long id) {
        return userService.findById(id).map(UserResponseV1::from);
    }
}

// Version 2 — different response shape
@RestController
@RequestMapping("/api/v2/users")
public class UserControllerV2 {

    @GetMapping("/{id}")
    public Mono<UserResponseV2> getUser(@PathVariable Long id) {
        return userService.findById(id).map(UserResponseV2::from);
    }
}

// Shared service layer — different mapping per version
public record UserResponseV1(Long id, String email, String name) {
    public static UserResponseV1 from(UserEntity entity) {
        return new UserResponseV1(entity.getId(), entity.getEmail(), entity.getName());
    }
}

public record UserResponseV2(
    Long id,
    String email,
    String name,
    String displayName,
    ProfileResponse profile
) {
    public static UserResponseV2 from(UserEntity entity) {
        return new UserResponseV2(
            entity.getId(), entity.getEmail(), entity.getName(),
            entity.getDisplayName(),
            ProfileResponse.from(entity.getProfile())
        );
    }
}
```

### Versioning Guidelines

- **v1 is forever** — once published, maintain backward compatibility
- **Minor changes** — add fields (non-breaking), deprecate with sunset header
- **Breaking changes** → new version (v2)
- **Deprecation**: announce early, provide migration guide, set `Sunset` header
- **Max 2 active versions** — maintain at most 2 concurrent versions

```java
// Sunset header for deprecated version
@GetMapping("/{id}")
public Mono<ResponseEntity<UserResponseV1>> getUser(@PathVariable Long id) {
    return userService.findById(id)
        .map(UserResponseV1::from)
        .map(user -> ResponseEntity.ok()
            .header("Sunset", "Sat, 01 Jan 2025 00:00:00 GMT")
            .header("Deprecation", "true")
            .header("Link", "</api/v2/users>; rel=\"successor-version\"")
            .body(user));
}
```

---

## Rate Limiting

### Rate Limit Headers

```java
@Component
public class RateLimitFilter implements WebFilter {

    private final RateLimiter rateLimiter; // e.g., Bucket4j, Resilience4j

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String clientId = extractClientId(exchange);

        return Mono.fromCallable(() -> rateLimiter.tryConsume(clientId))
            .flatMap(result -> {
                var response = exchange.getResponse();
                response.getHeaders().add("X-RateLimit-Limit", String.valueOf(result.limit()));
                response.getHeaders().add("X-RateLimit-Remaining", String.valueOf(result.remaining()));
                response.getHeaders().add("X-RateLimit-Reset", String.valueOf(result.resetAt()));

                if (!result.allowed()) {
                    response.setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                    response.getHeaders().add("Retry-After", String.valueOf(result.retryAfterSeconds()));
                    return response.setComplete();
                }

                return chain.filter(exchange);
            });
    }

    private String extractClientId(ServerWebExchange exchange) {
        // By API key, user ID, or IP
        return Optional.ofNullable(exchange.getRequest().getHeaders().getFirst("X-Api-Key"))
            .orElse(exchange.getRequest().getRemoteAddress().getAddress().getHostAddress());
    }
}
```

### Rate Limit Response Headers

```
HTTP/1.1 200 OK
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1703280000

HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1703280000
Retry-After: 60
```

---

## OpenAPI Documentation

### Configuration

```yaml
# application.yml
springdoc:
  api-docs:
    path: /api-docs
  swagger-ui:
    path: /swagger-ui.html
    tags-sorter: alpha
    operations-sorter: method
  default-consumes-media-type: application/json
  default-produces-media-type: application/json
```

```java
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
            .info(new Info()
                .title("User Service API")
                .version("1.0.0")
                .description("User management REST API")
                .contact(new Contact()
                    .name("API Team")
                    .email("api@example.com")))
            .addSecurityItem(new SecurityRequirement().addList("Bearer"))
            .components(new Components()
                .addSecuritySchemes("Bearer", new SecurityScheme()
                    .type(SecurityScheme.Type.HTTP)
                    .scheme("bearer")
                    .bearerFormat("JWT")));
    }
}
```

### Annotating Endpoints

```java
@RestController
@RequestMapping("/api/v1/users")
@Tag(name = "Users", description = "User management operations")
@RequiredArgsConstructor
public class UserController {

    @Operation(
        summary = "Get user by ID",
        description = "Returns a single user by their unique identifier",
        responses = {
            @ApiResponse(responseCode = "200", description = "User found",
                content = @Content(schema = @Schema(implementation = UserResponse.class))),
            @ApiResponse(responseCode = "404", description = "User not found",
                content = @Content(schema = @Schema(implementation = ProblemDetail.class)))
        }
    )
    @GetMapping("/{id}")
    public Mono<ResponseEntity<UserResponse>> getUser(
            @Parameter(description = "User ID", example = "123")
            @PathVariable Long id) {
        return userService.findById(id)
            .map(UserResponse::from)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @Operation(summary = "Create user")
    @ApiResponse(responseCode = "201", description = "User created")
    @ApiResponse(responseCode = "400", description = "Validation error")
    @ApiResponse(responseCode = "409", description = "Email already exists")
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserResponse> create(
            @Valid @RequestBody Mono<CreateUserRequest> request) {
        return request.flatMap(userService::create).map(UserResponse::from);
    }
}
```

---

## Input Validation

### Bean Validation

```java
public record CreateUserRequest(
    @NotBlank(message = "Email is required")
    @Email(message = "Must be a valid email")
    String email,

    @NotBlank(message = "Name is required")
    @Size(min = 2, max = 100, message = "Name must be 2-100 characters")
    String name,

    @NotNull(message = "Role is required")
    UserRole role,

    @Pattern(regexp = "^\\+?[1-9]\\d{1,14}$", message = "Invalid phone number")
    String phone,

    @Min(value = 0, message = "Age must be non-negative")
    @Max(value = 150, message = "Age must be <= 150")
    Integer age
) {}
```

### Custom Validator

```java
// Custom annotation
@Documented
@Constraint(validatedBy = UniqueEmailValidator.class)
@Target({ElementType.FIELD})
@Retention(RetentionPolicy.RUNTIME)
public @interface UniqueEmail {
    String message() default "Email already exists";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

// Validator implementation
@Component
@RequiredArgsConstructor
public class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, String> {

    private final UserRepository userRepository;

    @Override
    public boolean isValid(String email, ConstraintValidatorContext context) {
        if (email == null) return true;
        // Note: blocking in validator — consider async validation in service layer instead
        return !userRepository.existsByEmail(email).block();
    }
}

// Usage
public record CreateUserRequest(
    @NotBlank @Email @UniqueEmail
    String email,
    // ...
) {}
```

### Validation in Handler (Router Function Style)

```java
@Component
@RequiredArgsConstructor
public class UserHandler {

    private final Validator validator;

    public Mono<ServerResponse> create(ServerRequest request) {
        return request.bodyToMono(CreateUserRequest.class)
            .flatMap(body -> {
                var errors = new BeanPropertyBindingResult(body, "createUserRequest");
                validator.validate(body, errors);
                if (errors.hasErrors()) {
                    return ServerResponse.badRequest()
                        .bodyValue(toFieldErrors(errors));
                }
                return userService.create(body)
                    .map(UserResponse::from)
                    .flatMap(user -> ServerResponse.created(
                            URI.create("/api/v1/users/" + user.id()))
                        .bodyValue(user));
            });
    }

    private List<FieldError> toFieldErrors(Errors errors) {
        return errors.getFieldErrors().stream()
            .map(e -> new FieldError(e.getField(), e.getDefaultMessage(), e.getRejectedValue()))
            .toList();
    }
}
```

---

## Exception Handling

### Global Exception Handler (WebFlux)

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(WebExchangeBindException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Mono<ProblemDetail> handleValidation(WebExchangeBindException ex, ServerWebExchange exchange) {
        var problem = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST);
        problem.setTitle("Validation Error");
        problem.setDetail("Request validation failed");
        problem.setInstance(URI.create(exchange.getRequest().getPath().value()));

        var errors = ex.getFieldErrors().stream()
            .map(e -> Map.of(
                "field", e.getField(),
                "message", Objects.requireNonNull(e.getDefaultMessage()),
                "rejectedValue", String.valueOf(e.getRejectedValue())
            ))
            .toList();
        problem.setProperty("errors", errors);

        return Mono.just(problem);
    }

    @ExceptionHandler(NotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Mono<ProblemDetail> handleNotFound(NotFoundException ex, ServerWebExchange exchange) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Not Found");
        problem.setInstance(URI.create(exchange.getRequest().getPath().value()));
        return Mono.just(problem);
    }

    @ExceptionHandler(DuplicateResourceException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public Mono<ProblemDetail> handleDuplicate(DuplicateResourceException ex, ServerWebExchange exchange) {
        var problem = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.getMessage());
        problem.setTitle("Conflict");
        problem.setInstance(URI.create(exchange.getRequest().getPath().value()));
        return Mono.just(problem);
    }

    @ExceptionHandler(AccessDeniedException.class)
    @ResponseStatus(HttpStatus.FORBIDDEN)
    public Mono<ProblemDetail> handleAccessDenied(AccessDeniedException ex) {
        return Mono.just(ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, "Access denied"));
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public Mono<ProblemDetail> handleAll(Exception ex) {
        log.error("Unhandled exception", ex);
        return Mono.just(ProblemDetail.forStatusAndDetail(
            HttpStatus.INTERNAL_SERVER_ERROR, "An unexpected error occurred"));
    }
}
```

### Custom Exception Classes

```java
public class NotFoundException extends RuntimeException {
    public NotFoundException(String resource, Object id) {
        super(resource + " not found: " + id);
    }
}

public class DuplicateResourceException extends RuntimeException {
    public DuplicateResourceException(String resource, String field, Object value) {
        super(resource + " with " + field + " '" + value + "' already exists");
    }
}

public class BadRequestException extends RuntimeException {
    public BadRequestException(String message) {
        super(message);
    }
}
```

---

## Content Negotiation

### JSON + CSV Export

```java
@GetMapping(value = "/users/export", produces = {"application/json", "text/csv"})
public Mono<ResponseEntity<byte[]>> exportUsers(
        @RequestHeader(value = "Accept", defaultValue = "application/json") String accept) {

    return userService.findAll()
        .map(UserResponse::from)
        .collectList()
        .map(users -> {
            if (accept.contains("text/csv")) {
                byte[] csv = toCsv(users);
                return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType("text/csv"))
                    .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=users.csv")
                    .body(csv);
            }
            byte[] json = objectMapper.writeValueAsBytes(users);
            return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .body(json);
        });
}

private byte[] toCsv(List<UserResponse> users) {
    var sb = new StringBuilder("id,email,name,role,active,createdAt\n");
    for (var u : users) {
        sb.append(String.format("%d,%s,%s,%s,%s,%s\n",
            u.id(), u.email(), u.name(), u.role(), u.active(), u.createdAt()));
    }
    return sb.toString().getBytes(StandardCharsets.UTF_8);
}
```

---

## File Upload / Download

### Reactive File Upload

```java
@PostMapping(value = "/users/{id}/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
public Mono<ResponseEntity<Void>> uploadAvatar(
        @PathVariable Long id,
        @RequestPart("file") Mono<FilePart> fileMono) {

    return fileMono.flatMap(file -> {
        // Validate file
        String filename = file.filename();
        if (!filename.matches(".*\\.(jpg|jpeg|png|webp)$")) {
            return Mono.error(new BadRequestException("Invalid file type"));
        }

        Path dest = Path.of("/uploads/avatars", id + "_" + filename);
        return file.transferTo(dest)
            .then(userService.updateAvatar(id, dest.toString()))
            .thenReturn(ResponseEntity.ok().<Void>build());
    });
}

// Streaming upload (large files)
@PostMapping(value = "/files", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
public Mono<FileResponse> uploadLargeFile(@RequestPart("file") Mono<FilePart> fileMono) {
    return fileMono.flatMap(file -> {
        String fileId = UUID.randomUUID().toString();
        Path dest = Path.of("/uploads", fileId);

        return DataBufferUtils.write(file.content(), dest,
                StandardOpenOption.CREATE, StandardOpenOption.WRITE)
            .then(Mono.just(new FileResponse(fileId, file.filename())));
    });
}
```

### Reactive File Download

```java
@GetMapping("/files/{id}")
public Mono<ResponseEntity<Flux<DataBuffer>>> downloadFile(@PathVariable String id) {
    return fileService.getFileInfo(id)
        .map(fileInfo -> {
            Flux<DataBuffer> fileContent = DataBufferUtils.read(
                new FileSystemResource(fileInfo.path()),
                new DefaultDataBufferFactory(),
                4096);

            return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .header(HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"" + fileInfo.originalName() + "\"")
                .header(HttpHeaders.CONTENT_LENGTH, String.valueOf(fileInfo.size()))
                .body(fileContent);
        });
}
```

---

## Idempotency

### Idempotency Keys for POST Endpoints

```java
// Client sends: Idempotency-Key: <unique-uuid>
@PostMapping("/payments")
public Mono<ResponseEntity<PaymentResponse>> createPayment(
        @RequestHeader("Idempotency-Key") String idempotencyKey,
        @Valid @RequestBody Mono<CreatePaymentRequest> request) {

    // Check if this key was already processed
    return idempotencyService.get(idempotencyKey)
        .map(cached -> ResponseEntity.ok(cached))
        .switchIfEmpty(
            request.flatMap(req -> paymentService.create(req)
                .map(PaymentResponse::from)
                .flatMap(response -> idempotencyService
                    .store(idempotencyKey, response, Duration.ofHours(24))
                    .thenReturn(ResponseEntity.status(HttpStatus.CREATED).body(response)))
            )
        );
}

// Idempotency service (Redis-backed)
@Service
@RequiredArgsConstructor
public class IdempotencyService {

    private final ReactiveRedisTemplate<String, String> redis;
    private final ObjectMapper objectMapper;

    public Mono<PaymentResponse> get(String key) {
        return redis.opsForValue()
            .get("idempotency:" + key)
            .map(json -> parseJson(json, PaymentResponse.class));
    }

    public Mono<Boolean> store(String key, Object response, Duration ttl) {
        return redis.opsForValue()
            .set("idempotency:" + key, toJson(response), ttl);
    }
}
```

---

## Bulk Operations

### Batch Create

```java
// POST /api/v1/users/bulk
@PostMapping("/bulk")
public Mono<BulkResponse<UserResponse>> bulkCreate(
        @Valid @RequestBody Mono<BulkCreateRequest> request) {

    return request.flatMap(bulk -> {
        if (bulk.items().size() > 100) {
            return Mono.error(new BadRequestException("Max 100 items per batch"));
        }

        return Flux.fromIterable(bulk.items())
            .flatMap(item -> userService.create(item)
                .map(user -> BulkResult.success(UserResponse.from(user)))
                .onErrorResume(e -> Mono.just(
                    BulkResult.failure(item.email(), e.getMessage())
                )),
                10) // concurrency limit
            .collectList()
            .map(BulkResponse::new);
    });
}

public record BulkCreateRequest(
    @NotEmpty @Size(max = 100)
    List<@Valid CreateUserRequest> items
) {}

public record BulkResponse<T>(List<BulkResult<T>> results) {
    public long successCount() {
        return results.stream().filter(BulkResult::success).count();
    }
    public long failureCount() {
        return results.stream().filter(r -> !r.success()).count();
    }
}

public record BulkResult<T>(
    boolean success,
    T data,
    String identifier,
    String error
) {
    public static <T> BulkResult<T> success(T data) {
        return new BulkResult<>(true, data, null, null);
    }
    public static <T> BulkResult<T> failure(String identifier, String error) {
        return new BulkResult<>(false, null, identifier, error);
    }
}
```

### Batch Delete

```java
// DELETE /api/v1/users/bulk?ids=1,2,3
@DeleteMapping("/bulk")
@ResponseStatus(HttpStatus.NO_CONTENT)
public Mono<Void> bulkDelete(@RequestParam List<Long> ids) {
    if (ids.size() > 100) {
        return Mono.error(new BadRequestException("Max 100 items per batch"));
    }
    return userService.deleteByIds(ids);
}
```

---

## Long-Running Operations

### Async with Status Polling

```java
// Step 1: Submit operation → 202 Accepted
@PostMapping("/reports/generate")
public Mono<ResponseEntity<OperationStatus>> generateReport(
        @Valid @RequestBody Mono<ReportRequest> request) {

    return request.flatMap(req -> {
        String operationId = UUID.randomUUID().toString();

        // Start async processing
        reportService.generateAsync(operationId, req)
            .subscribeOn(Schedulers.boundedElastic())
            .subscribe();

        var status = new OperationStatus(operationId, "PENDING", null, null);
        return Mono.just(ResponseEntity
            .accepted()
            .header("Location", "/api/v1/operations/" + operationId)
            .body(status));
    });
}

// Step 2: Poll for status → 200 (in progress) or 303 (complete with redirect)
@GetMapping("/operations/{id}")
public Mono<ResponseEntity<OperationStatus>> getOperationStatus(@PathVariable String id) {
    return operationService.getStatus(id)
        .map(status -> switch (status.state()) {
            case "COMPLETED" -> ResponseEntity
                .status(HttpStatus.SEE_OTHER)
                .header("Location", status.resultUrl())
                .body(status);
            case "FAILED" -> ResponseEntity
                .status(HttpStatus.OK)
                .body(status);
            default -> ResponseEntity.ok(status);
        })
        .defaultIfEmpty(ResponseEntity.notFound().build());
}

public record OperationStatus(
    String operationId,
    String state,           // PENDING, PROCESSING, COMPLETED, FAILED
    String resultUrl,       // URL to fetch result when COMPLETED
    String error            // Error message when FAILED
) {}
```

---

## WebFlux Router Functions

### Complete Router + Handler Example

```java
@Configuration
public class UserRouter {

    @Bean
    public RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .path("/api/v1/users", builder -> builder
                .GET("", handler::list)
                .GET("/{id}", handler::getById)
                .POST("", contentType(APPLICATION_JSON), handler::create)
                .PUT("/{id}", contentType(APPLICATION_JSON), handler::replace)
                .PATCH("/{id}", contentType(APPLICATION_JSON), handler::update)
                .DELETE("/{id}", handler::delete)
                .POST("/bulk", contentType(APPLICATION_JSON), handler::bulkCreate)
                .POST("/{id}/avatar",
                    contentType(MediaType.MULTIPART_FORM_DATA), handler::uploadAvatar)
            )
            .filter((request, next) -> {
                // Logging filter
                log.info("{} {}", request.method(), request.path());
                return next.handle(request);
            })
            .build();
    }
}
```

---

## Contract Testing

### Spring Cloud Contract (Provider Side)

```groovy
// contracts/shouldReturnUser.groovy
Contract.make {
    description "should return user by ID"
    request {
        method GET()
        url "/api/v1/users/1"
        headers {
            contentType applicationJson()
        }
    }
    response {
        status OK()
        headers {
            contentType applicationJson()
        }
        body(
            id: 1,
            email: "test@example.com",
            name: "Test User",
            role: "USER",
            active: true
        )
    }
}
```

```java
// Base test class for contract verification
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
public abstract class ContractVerifierBase {

    @Autowired
    WebTestClient webTestClient;

    @MockBean
    UserService userService;

    @BeforeEach
    void setup() {
        when(userService.findById(1L))
            .thenReturn(Mono.just(new UserEntity(1L, "test@example.com", "Test User",
                UserRole.USER, true, Instant.now(), Instant.now())));
    }
}
```

### Pact (Consumer Side)

```java
@ExtendWith(PactConsumerTestExt.class)
@PactTestFor(providerName = "user-service")
class UserClientPactTest {

    @Pact(consumer = "order-service")
    public V4Pact getUserPact(PactDslWithProvider builder) {
        return builder
            .given("user with id 1 exists")
            .uponReceiving("a request to get user 1")
                .path("/api/v1/users/1")
                .method("GET")
            .willRespondWith()
                .status(200)
                .body(new PactDslJsonBody()
                    .integerType("id", 1)
                    .stringType("email", "test@example.com")
                    .stringType("name", "Test User"))
            .toPact(V4Pact.class);
    }

    @Test
    @PactTestFor(pactMethod = "getUserPact")
    void shouldGetUser(MockServer mockServer) {
        var client = WebClient.create(mockServer.getUrl());
        var user = client.get()
            .uri("/api/v1/users/1")
            .retrieve()
            .bodyToMono(UserResponse.class)
            .block();

        assertThat(user.id()).isEqualTo(1L);
        assertThat(user.email()).isEqualTo("test@example.com");
    }
}
```

---

## HATEOAS (When Appropriate)

```java
// Only add HATEOAS when clients actually navigate links
// Typically useful for: public APIs, hypermedia-driven UIs, discovery APIs
// Typically overkill for: internal microservice APIs, mobile backends

public record UserResponse(
    Long id,
    String email,
    String name,
    Map<String, LinkInfo> _links
) {
    public static UserResponse from(UserEntity entity) {
        var links = Map.of(
            "self", new LinkInfo("/api/v1/users/" + entity.getId(), "GET"),
            "orders", new LinkInfo("/api/v1/users/" + entity.getId() + "/orders", "GET"),
            "update", new LinkInfo("/api/v1/users/" + entity.getId(), "PUT"),
            "delete", new LinkInfo("/api/v1/users/" + entity.getId(), "DELETE")
        );
        return new UserResponse(
            entity.getId(), entity.getEmail(), entity.getName(), links);
    }
}

public record LinkInfo(String href, String method) {}
```

---

## Checklist

- [ ] Resources named with plural nouns, kebab-case
- [ ] Correct HTTP methods and status codes
- [ ] RFC 7807 Problem Details for all errors
- [ ] Input validation with Bean Validation (@Valid)
- [ ] Global exception handler (@RestControllerAdvice or ErrorWebExceptionHandler)
- [ ] Pagination for all list endpoints (cursor-based preferred)
- [ ] Sort field whitelist (prevent SQL injection)
- [ ] API version in URL path (/api/v1/...)
- [ ] Rate limiting with standard headers
- [ ] OpenAPI/Swagger documentation
- [ ] Idempotency keys for non-idempotent payment/create endpoints
- [ ] Bulk operations capped (max 100 items)
- [ ] Long-running operations use async + polling pattern
- [ ] File uploads validated (type, size)
- [ ] Reactive file streaming (not buffering entire file)
- [ ] Contract tests for API consumers
- [ ] Sunset header on deprecated versions