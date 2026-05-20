---
name: code-review-mvc
description: Spring MVC (servlet stack) code review rules — controller, validation, response, service, repository, transaction, configuration, exception handling, security. Rule IDs MVC-*. Load when project uses Spring MVC. Cite by ID in review.
globs: "*.java"
applicability:
  always: false
  triggers:
    files_match: ["**/*Controller.java", "**/*Service.java", "**/*Repository.java", "**/*ControllerAdvice.java"]
    code_patterns: ["@RestController", "@Controller", "@Service", "JpaRepository", "@Transactional", "@RequestMapping"]
    task_keywords: ["spring mvc", "servlet", "controller", "@RestController", "JPA", "hibernate", "@Transactional"]
    related_rules:
      - rules/java/code-review-core.md
      - rules/java/api-design.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 90%+: project uses Spring MVC (verified: spring-boot-starter-web in build.gradle, JpaRepository or @RestController in src/)
  ZERO: project is pure WebFlux (reactive)
---

# Code Review — Spring MVC (`MVC-*`)

> Servlet stack rules. Load alongside `code-review-core.md`. Cite ID in review (`[P0][MVC-TX-001]`).

## 2.1. Controller Layer (`MVC-CTL`)

### MVC-CTL-001 — Controller stateless

Spring MVC singleton bean on thread-per-request. **NEVER** put mutable instance fields in a controller (race condition).

### MVC-CTL-002 — Controller thin, delegate to service

Controller does 4 things: (1) Bind input (2) Validate (3) Delegate to service (4) Map result → response DTO.

Business logic, transactions, side effects → service.

```java
@PostMapping
public ResponseEntity<OrderResponse> create(@Valid @RequestBody CreateOrderRequest req,
                                            @AuthenticationPrincipal User user) {
    Order created = orderService.create(req.toCommand(), user);
    return ResponseEntity.status(HttpStatus.CREATED).body(OrderResponse.from(created));
}
```

### MVC-CTL-003 — Specific HTTP annotation

**Bad**: `@RequestMapping(value = "/orders", method = RequestMethod.POST)` — verbose
**Good**: `@PostMapping("/orders")`

`@GetMapping`, `@PostMapping`, `@PutMapping`, `@DeleteMapping`, `@PatchMapping`.

### MVC-CTL-004 — RESTful path

```
GET    /merchants/{id}                       # ✅ get one
GET    /merchants/{id}/applications          # ✅ nested collection
POST   /merchants/{id}/applications          # ✅ nested create
PUT    /merchants/{id}                       # ✅ full update
PATCH  /merchants/{id}                       # ✅ partial update
DELETE /merchants/{id}                       # ✅ delete

POST   /merchants/getMerchant                # ❌ RPC-style
```

Verb in HTTP method, not in path.

### MVC-CTL-005 — Consistent API versioning

Pick one strategy: Path (`/v1/merchants`) | Header (`Accept: application/vnd.acme.v1+json`) | Query. Path versioning is the simplest.

## 2.2. Validation (`MVC-VAL`)

### MVC-VAL-001 — @Valid on @RequestBody, @Validated on class

```java
@RestController
@Validated   // ✅ for @PathVariable, @RequestParam
public class OrderController {
    @PostMapping
    public Order create(@Valid @RequestBody CreateOrderRequest req) { ... }

    @GetMapping("/{id}")
    public Order get(@PathVariable @Min(1) Long id) { ... }
}
```

### MVC-VAL-002 — Validation group for create vs update

```java
public interface OnCreate {}
public interface OnUpdate {}

public class MerchantRequest {
    @NotNull(groups = OnCreate.class)
    private String taxCode;
    @Email
    private String email;
}

@PostMapping
public void create(@Validated(OnCreate.class) @RequestBody MerchantRequest req) {}
```

### MVC-VAL-003 — Custom validator for business rules

```java
@Constraint(validatedBy = VnPhoneValidator.class)
@Target({FIELD, PARAMETER}) @Retention(RUNTIME)
public @interface VnPhone { String message() default "..."; }

public class VnPhoneValidator implements ConstraintValidator<VnPhone, String> {
    private static final Pattern P = Pattern.compile("^(0|\\+84)[0-9]{9}$");
    public boolean isValid(String value, ConstraintValidatorContext ctx) {
        return value == null || P.matcher(value).matches();
    }
}
```

Bean Validation for format & required. Service layer for cross-field business rules.

## 2.3. Response (`MVC-RSP`)

### MVC-RSP-001 — DTO, never leak entity

**Bad**: `return merchantRepository.findById(id);` — leaks entity with internal fields
**Good**: `return merchantService.findById(id).map(MerchantResponse::from).orElseThrow(...);`

Entities have `version`, `createdBy`, internal flags — should not be exposed. DTOs let entity evolve without breaking API.

### MVC-RSP-002 — Consistent error envelope

```json
{
  "code": "PHONE_DUPLICATE",
  "message": "Phone number already in use",
  "errors": [{ "field": "phoneNumber", "code": "DUPLICATE", "message": "..." }],
  "traceId": "abc-123-def"
}
```

Define once in `@RestControllerAdvice`. Use across the entire project.

## 2.4. Service Layer (`MVC-SVC`)

### MVC-SVC-001 — @Transactional on impl, not interface

`@Transactional` on interface does not work with default CGLIB proxy. AspectJ works, but JDK proxy default does not. Placing on impl is the safe default.

### MVC-SVC-002 — @Transactional settings

```java
@Transactional(
    propagation = Propagation.REQUIRED,
    isolation = Isolation.READ_COMMITTED,
    readOnly = false,
    rollbackFor = Exception.class,  // ✅ rolls back checked too
    timeout = 30                     // ✅ explicit
)
```

Default `rollbackFor` only rolls back unchecked. Explicit `Exception.class` gives consistent behavior. `readOnly = true` for query methods — Hibernate skips dirty check.

### MVC-SVC-003 — Self-invocation bypasses proxy

**Bad**: `public void outer() { inner(); }` — direct call, `@Transactional` does NOT apply.

**Good option 1 (split class)**:
```java
@Service
public class OrderService {
    private final OrderTransactionService txService;
    public void outer() { txService.inner(); }   // ✅ through proxy
}
```

**Good option 2 (self-injection)**:
```java
@Autowired private OrderService self;
public void outer() { self.inner(); }
```

### MVC-SVC-004 — Idempotency for retry-able operations

Service methods that can be retried (network error, message redelivery) must be:
- Idempotent: multiple calls = same result
- Or deduplicated via idempotency key

Especially for POST resource creation, money operations.

## 2.5. Repository Layer (`MVC-REP`)

### MVC-REP-001 — Method naming ≤ 3 fields

`List<Order> findByCustomerIdAndStatus(...)` — OK
`findByCustomerIdAndStatusAndCreatedAtBetweenAndAmountGreaterThan(...)` — too long

Over 3 fields → use `@Query`:
```java
@Query("SELECT o FROM Order o WHERE o.customerId = :customerId AND o.status IN :statuses AND o.createdAt BETWEEN :from AND :to")
List<Order> searchOrders(@Param("customerId") String customerId, ...);
```

### MVC-REP-002 — JPQL > native unless DB-specific feature needed

JPQL is portable, type-safe with entities. Native SQL only when:
- DB-specific feature needed (window function, CTE, full-text)
- Performance tuning with hints
- DDL/maintenance

### MVC-REP-003 — List query must be pageable

**Bad**: `List<Order> findByCustomerId(String customerId);` — unbounded
**Good**: `Page<Order> findByCustomerId(String customerId, Pageable pageable);` or `Slice<Order>` (no total count)

A 10-year customer with 100k orders → load all = OOM.

### MVC-REP-004 — N+1 query

**Bad — N+1**: `orders.forEach(o -> o.getItems().size());` → N queries

**Good — fetch join**: `@Query("SELECT DISTINCT o FROM Order o LEFT JOIN FETCH o.items")`

**Good — entity graph**: `@EntityGraph(attributePaths = {"items"})`

Enable `spring.jpa.properties.hibernate.generate_statistics=true` in dev to detect.

## 2.6. Transaction Boundaries (`MVC-TX`)

### MVC-TX-001 — Narrow transaction

**Bad**: HTTP call inside `@Transactional` method → holds DB connection + row lock for seconds → connection pool exhaustion.

**Good**: Short TX for DB ops. External call OUTSIDE TX. Compose two TXs if needed.

```java
public Order processOrder(Long id) {
    Order order = loadOrder(id);                  // TX1 short
    PaymentResult result = paymentClient.charge(order);   // outside TX
    return updateOrderWithPayment(id, result);    // TX2 short
}
```

### MVC-TX-002 — Outbox pattern for domain events

**Bad — dual-write**:
```java
@Transactional
public Order place(Order order) {
    repository.save(order);
    kafkaTemplate.send("orders", order);   // ❌ Kafka has msg but DB rolled back
    return order;
}
```

**Good — Outbox**:
```java
@Transactional
public Order place(Order order) {
    repository.save(order);
    outboxRepository.save(new OutboxEvent("OrderPlaced", order));   // ✅ same TX
    return order;
}
// Separate poller/CDC publishes outbox → Kafka, deletes row on ACK
```

### MVC-TX-003 — Optimistic lock with @Version

```java
@Entity
public class Order {
    @Id private Long id;
    @Version private Integer version;   // ✅ JPA auto-increment + check
}
```

Catch `OptimisticLockingFailureException` → retry or return 409 Conflict.

### MVC-TX-004 — Pessimistic lock when serialization needed

```java
@Lock(LockModeType.PESSIMISTIC_WRITE)
@Query("SELECT a FROM Account a WHERE a.id = :id")
Optional<Account> findByIdForUpdate(@Param("id") Long id);
```

For hot rows (account balance). Lock held until TX end → keep TX short.

## 2.7. Configuration (`MVC-CFG`)

### MVC-CFG-001 — @ConfigurationProperties instead of @Value

**Bad**: scattered `@Value("${app.payment.timeout}")` — no type safety

**Good**:
```java
@ConfigurationProperties(prefix = "app.payment")
public record PaymentProperties(
    @NotNull Duration timeout,
    @NotBlank String url,
    @Min(1) int maxRetries
) {}
```

Type-safe, validatable, IDE autocomplete, grouped.

### MVC-CFG-002 — Profile for env-specific config

`application.yml` common + `application-prod.yml` / `application-test.yml`. Activate: `SPRING_PROFILES_ACTIVE=prod` or `--spring.profiles.active=prod`.

### MVC-CFG-003 — No hardcoded secrets

```yaml
spring:
  datasource:
    password: ${DB_PASSWORD}    # env var or Vault
```

Local dev: `.env` (gitignored) or IDE run config.

## 2.8. Exception Handling (`MVC-EXC`)

### MVC-EXC-001 — @RestControllerAdvice global handler

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(...) { ... }

    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ErrorResponse> handleBusiness(BusinessException e) {
        log.warn("business error code={} message={}", e.getCode(), e.getMessage());
        return ResponseEntity.status(e.getCode().status())
            .body(new ErrorResponse(e.getCode().name(), e.getMessage(), List.of(), traceId()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleUnexpected(Exception e) {
        log.error("unexpected error", e);   // ✅ stack trace SERVER SIDE
        return ResponseEntity.internalServerError()
            .body(new ErrorResponse("INTERNAL_ERROR", "Internal error", List.of(), traceId()));
    }
}
```

### MVC-EXC-002 — HTTP status mapping

| Status | When |
|--------|------|
| 400 | Validation, malformed input |
| 401 | Not authenticated (missing/invalid token) |
| 403 | Authenticated but no permission |
| 404 | Resource not found |
| 409 | Concurrent modification, duplicate |
| 422 | Business rule violation (e.g., AML not clean) |
| 429 | Rate limit |
| 500 | Bug, dependency failure |
| 503 | Maintenance, overload |

### MVC-EXC-003 — Never leak stack trace to production

`server.error.include-stacktrace=never` in prod. Stack trace lives in server log only.

## 2.9. Security (`MVC-SEC`)

### MVC-SEC-001 — @PreAuthorize for method authz

```java
@PreAuthorize("hasRole('MERCHANT_REVIEWER')")
public Application approve(String appId) { ... }

@PreAuthorize("hasRole('ADMIN') or #userId == authentication.principal.id")
public User getUser(String userId) { ... }
```

Enable `@EnableMethodSecurity` on a config class.

### MVC-SEC-002 — CSRF for stateful endpoints

CSRF token for session-based auth. Stateless JWT API may disable, but still verify Origin/Referer for cookie-based.

### MVC-SEC-003 — Rate limit

At the gateway (Nginx, Kong, API Gateway) is ideal. Or at filter level via Bucket4j/Resilience4j RateLimiter.

## Related

- `rules/java/code-review-core.md` — CORE-* foundation rules (always apply)
- `rules/java/code-review-crosscut.md` — XCT-* + PR checklist + severity
- `rules/java/api-design.md` — REST conventions deep dive
- `skills/spring-mvc-patterns` — MVC implementation patterns
