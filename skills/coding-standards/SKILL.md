---
name: coding-standards
description: Universal coding standards, best practices, and patterns for Java Spring WebFlux/MVC development. Use proactively when reviewing code, implementing features, writing tests, or setting up project structure. Covers naming, immutability, error handling, validation, reactive patterns, code smells, and CQRS project organization.
---

# Coding Standards & Best Practices

Universal coding standards for Java Spring projects.

## Core Principles

| Principle | Rule |
|-----------|------|
| **Readability First** | Self-documenting names over comments; consistent formatting |
| **KISS** | Simplest solution that works; avoid clever code |
| **DRY** | Extract repeated logic; no copy-paste |
| **YAGNI** | No speculative features; add complexity only when required |
| **Single Responsibility** | One class/method = one purpose |

---

## Naming Conventions

```java
// Variables — descriptive nouns
String marketSearchQuery = "election";     // ✅
boolean isUserAuthenticated = true;        // ✅
String q = "election"; boolean flag = true;  // ❌

// Methods — verb-noun
Mono<MarketData> fetchMarketData(String id) { }  // ✅
boolean isValidEmail(String email) { }           // ✅
Mono<MarketData> market(String id) { }           // ❌

// Classes — clear roles
public interface MarketRepository { }                  // ✅
public record CreateMarketRequest(String name) { }     // ✅
public class MarketNotFoundException extends RuntimeException { }  // ✅
public interface Repo { }  public class Request { }    // ❌
```

---

## Immutability (CRITICAL)

```java
// ✅ Immutable record with @Builder + @With
@Builder(toBuilder = true) @With
public record Order(String id, String customerId, OrderStatus status, BigDecimal total) {}

// Update = new instance
Order shipped = order.withStatus(OrderStatus.SHIPPED);
Order updated = order.toBuilder().status(OrderStatus.CONFIRMED).total(newTotal).build();

// ❌ Mutable class / mutation inside reactive chain
market.setStatus(MarketStatus.ACTIVE);  // WRONG in reactive

// ✅ Transform, don't mutate
return marketRepository.findById(id)
    .map(m -> m.withStatus(MarketStatus.ACTIVE))
    .flatMap(marketRepository::save);
```

---

## Error Handling

```java
// Domain exceptions — meaningful messages
public class MarketNotFoundException extends RuntimeException {
    public MarketNotFoundException(String id) { super("Market not found: " + id); }
}

// Reactive error handling
public Mono<Market> getMarket(String id) {
    return marketRepository.findById(id)
        .switchIfEmpty(Mono.error(new MarketNotFoundException(id)))
        .onErrorMap(DataAccessException.class, e -> new DatabaseException("DB error", e))
        .doOnError(e -> log.error("Error fetching market {}: {}", id, e.getMessage()));
}

// Fallback pattern
.onErrorResume(RedisException.class, e -> {
    log.warn("Redis unavailable, falling back to DB");
    return marketRepository.searchByName(query);
})
```

```java
// Global handler — RFC 7807 ProblemDetail
@RestControllerAdvice @Slf4j
public class GlobalExceptionHandler {
    @ExceptionHandler(MarketNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ProblemDetail handleNotFound(MarketNotFoundException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ProblemDetail handleAll(Exception ex) {
        log.error("Unexpected error", ex);
        return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR,
            "An unexpected error occurred");  // ← never expose internals
    }
}
```

---

## Input Validation

```java
// Request DTO with Bean Validation
public record CreateMarketRequest(
    @NotBlank @Size(min = 3, max = 200) String name,
    @NotBlank @Size(max = 2000) String description,
    @NotNull @Future Instant endDate,
    @NotEmpty List<@NotBlank String> categories
) {}

// Controller — @Validated on class, @Valid on @RequestBody
@RestController @Validated
public class MarketController {
    @PostMapping
    public Mono<ResponseEntity<Market>> create(@Valid @RequestBody CreateMarketRequest req) { ... }

    @GetMapping
    public Flux<Market> list(
        @RequestParam(defaultValue = "0") @Min(0) int offset,
        @RequestParam(defaultValue = "20") @Min(1) @Max(100) int limit) { ... }
}
```

---

## Reactive Best Practices

```java
// ✅ Parallel execution with Mono.zip
public Mono<DashboardData> getDashboard(String userId) {
    return Mono.zip(
        userService.findById(userId),
        marketService.findByUser(userId).collectList(),
        statsService.getForUser(userId)
    ).map(t -> new DashboardData(t.getT1(), t.getT2(), t.getT3()));
}

// ❌ Unnecessary sequential nesting
return userService.findById(userId)
    .flatMap(user -> marketService.findByUser(userId).collectList()
        .flatMap(markets -> statsService.getForUser(userId)
            .map(stats -> new DashboardData(user, markets, stats))));
```

---

## Code Smells (Fix These)

| Smell | Rule | Fix |
|-------|------|-----|
| **Long Method** | > 30 lines | Extract named private methods |
| **Deep Nesting** | > 3 levels | Early return / guard clauses |
| **Magic Numbers** | `if (count > 3)` | `private static final int MAX_RETRIES = 3` |
| **God Class** | Service doing payments + notifications + reports | One class, one purpose |
| **N+1 Queries** | `flatMap(m -> repo.findByMarketId(m.id()))` | Batch fetch with `findByMarketIdIn(ids)` |

```java
// Guard clauses > deep nesting
if (user == null) return Mono.error(new UnauthorizedException());
if (!user.isAdmin()) return Mono.error(new ForbiddenException());
if (market == null) return Mono.error(new NotFoundException());
// Do the work
```

---

## Comments — When and How

```java
// ✅ Explain WHY, not WHAT
// Use exponential backoff to avoid overwhelming the API during outages
long delay = Math.min(1000 * (long) Math.pow(2, retryCount), 30000);

// ❌ Stating the obvious
// Increment counter by 1
count++;
```

---

## Code Quality Checklist

Before any commit:

- [ ] All methods < 30 lines, classes < 400 lines
- [ ] Nesting depth < 4 levels
- [ ] No hardcoded values (use constants/config)
- [ ] No mutable state in reactive chains
- [ ] `@Valid` on all `@RequestBody` parameters
- [ ] Domain exceptions with meaningful messages
- [ ] No empty catch blocks
- [ ] No sensitive data in logs
- [ ] Tests written for new code

---

## References

Load as needed:

- **[references/project-structure.md](references/project-structure.md)** — CQRS + Hexagonal package structure, full directory tree, package naming conventions, JavaDoc examples, database projection patterns
