---
name: coding-standards
description: Universal coding standards, best practices, and patterns for Java Spring WebFlux/MVC development.
---

# Coding Standards & Best Practices

Universal coding standards applicable across all Java Spring projects.

## Code Quality Principles

### 1. Readability First

- Code is read more than written
- Clear variable and function names
- Self-documenting code preferred over comments
- Consistent formatting

### 2. KISS (Keep It Simple, Stupid)

- Simplest solution that works
- Avoid over-engineering
- No premature optimization
- Easy to understand > clever code

### 3. DRY (Don't Repeat Yourself)

- Extract common logic into methods
- Create reusable components
- Share utilities across modules
- Avoid copy-paste programming

### 4. YAGNI (You Aren't Gonna Need It)

- Don't build features before they're needed
- Avoid speculative generality
- Add complexity only when required
- Start simple, refactor when needed

## Java Naming Conventions

### Variable Naming

```java
// GOOD: Descriptive names
String marketSearchQuery = "election";
boolean isUserAuthenticated = true;
BigDecimal totalRevenue = new BigDecimal("1000.00");

// BAD: Unclear names
String q = "election";
boolean flag = true;
BigDecimal x = new BigDecimal("1000.00");
```

### Method Naming

```java
// GOOD: Verb-noun pattern
public Mono<MarketData> fetchMarketData(String marketId) { }
public double calculateSimilarity(double[] a, double[] b) { }
public boolean isValidEmail(String email) { }

// BAD: Unclear or noun-only
public Mono<MarketData> market(String id) { }
public double similarity(double[] a, double[] b) { }
public boolean email(String e) { }
```

### Class/Interface Naming

```java
// GOOD: Clear, descriptive names
public interface MarketRepository { }
public class MarketServiceImpl implements MarketService { }
public record CreateMarketRequest(String name, String description) { }
public class MarketNotFoundException extends RuntimeException { }

// BAD: Vague names
public interface Repo { }
public class Service { }
public record Request { }
```

## Immutability Pattern (CRITICAL)

### Use Records and Builders

```java
// GOOD: Immutable record with builder
@Builder(toBuilder = true)
public record Market(
    String id,
    String name,
    MarketStatus status,
    BigDecimal volume,
    Instant createdAt
) {}

// Update by creating new instance
Market updatedMarket = market.toBuilder()
    .status(MarketStatus.RESOLVED)
    .build();

// BAD: Mutable class
public class Market {
    private String name;
    public void setName(String name) { // Mutation!
        this.name = name;
    }
}
```

### @With for Partial Updates

```java
@With
@Builder
public record Order(
    String id,
    String customerId,
    OrderStatus status,
    BigDecimal total
) {}

// Create new instance with one field changed
Order shippedOrder = order.withStatus(OrderStatus.SHIPPED);
```

### Reactive Chains - Never Mutate

```java
// GOOD: Transform data, don't mutate
return marketRepository.findById(id)
    .map(market -> market.toBuilder()
        .status(MarketStatus.ACTIVE)
        .build())
    .flatMap(marketRepository::save);

// BAD: Mutating inside reactive chain
return marketRepository.findById(id)
    .map(market -> {
        market.setStatus(MarketStatus.ACTIVE); // WRONG!
        return market;
    });
```

## Error Handling

### Domain Exceptions

```java
// Define domain-specific exceptions
public class MarketNotFoundException extends RuntimeException {
    public MarketNotFoundException(String marketId) {
        super("Market not found: " + marketId);
    }
}

public class InsufficientBalanceException extends RuntimeException {
    public InsufficientBalanceException(BigDecimal required, BigDecimal available) {
        super(String.format("Insufficient balance: required %s, available %s", 
            required, available));
    }
}
```

### Reactive Error Handling

```java
// GOOD: Comprehensive error handling
public Mono<Market> getMarket(String id) {
    return marketRepository.findById(id)
        .switchIfEmpty(Mono.error(new MarketNotFoundException(id)))
        .onErrorMap(DataAccessException.class, 
            e -> new DatabaseException("Failed to fetch market", e))
        .doOnError(e -> log.error("Error fetching market {}: {}", id, e.getMessage()));
}

// Using onErrorResume for fallback
public Mono<List<Market>> searchMarkets(String query) {
    return vectorSearchService.search(query)
        .onErrorResume(RedisException.class, e -> {
            log.warn("Redis unavailable, falling back to DB search");
            return marketRepository.searchByName(query);
        });
}
```

### GlobalExceptionHandler

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(MarketNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(MarketNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
            .body(new ErrorResponse("NOT_FOUND", ex.getMessage()));
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorResponse> handleValidation(ConstraintViolationException ex) {
        String message = ex.getConstraintViolations().stream()
            .map(ConstraintViolation::getMessage)
            .collect(Collectors.joining(", "));
        return ResponseEntity.badRequest()
            .body(new ErrorResponse("VALIDATION_ERROR", message));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(Exception ex) {
        log.error("Unexpected error", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse("INTERNAL_ERROR", "An error occurred"));
    }
}

public record ErrorResponse(String code, String message) {}
```

## Input Validation

### Bean Validation

```java
public record CreateMarketRequest(
    @NotBlank(message = "Name is required")
    @Size(min = 3, max = 200, message = "Name must be 3-200 characters")
    String name,

    @NotBlank(message = "Description is required")
    @Size(max = 2000, message = "Description max 2000 characters")
    String description,

    @NotNull(message = "End date is required")
    @Future(message = "End date must be in the future")
    Instant endDate,

    @NotEmpty(message = "At least one category required")
    List<@NotBlank String> categories
) {}
```

### Controller Validation

```java
@RestController
@RequestMapping("/api/markets")
@Validated
public class MarketController {

    @PostMapping
    public Mono<ResponseEntity<Market>> createMarket(
            @Valid @RequestBody CreateMarketRequest request) {
        return marketService.create(request)
            .map(market -> ResponseEntity.status(HttpStatus.CREATED).body(market));
    }

    @GetMapping
    public Flux<Market> listMarkets(
            @RequestParam(defaultValue = "0") @Min(0) int offset,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int limit) {
        return marketService.findAll(offset, limit);
    }
}
```

### Custom Validators

```java
@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = ValidSlugValidator.class)
public @interface ValidSlug {
    String message() default "Invalid slug format";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

public class ValidSlugValidator implements ConstraintValidator<ValidSlug, String> {
    private static final Pattern SLUG_PATTERN = Pattern.compile("^[a-z0-9-]+$");

    @Override
    public boolean isValid(String value, ConstraintValidatorContext context) {
        return value != null && SLUG_PATTERN.matcher(value).matches();
    }
}
```

## Async/Reactive Best Practices

### Parallel Execution

```java
// GOOD: Parallel execution when possible
public Mono<DashboardData> getDashboard(String userId) {
    return Mono.zip(
        userService.findById(userId),
        marketService.findByUser(userId).collectList(),
        statsService.getForUser(userId)
    ).map(tuple -> new DashboardData(
        tuple.getT1(),
        tuple.getT2(),
        tuple.getT3()
    ));
}

// BAD: Sequential when unnecessary
public Mono<DashboardData> getDashboard(String userId) {
    return userService.findById(userId)
        .flatMap(user -> marketService.findByUser(userId).collectList()
            .flatMap(markets -> statsService.getForUser(userId)
                .map(stats -> new DashboardData(user, markets, stats))));
}
```

### Proper Mono/Flux Usage

```java
// GOOD: Use Flux for multiple items
public Flux<Market> findActiveMarkets() {
    return marketRepository.findByStatus(MarketStatus.ACTIVE);
}

// GOOD: Use Mono for single item
public Mono<Market> findById(String id) {
    return marketRepository.findById(id);
}

// GOOD: Convert Flux to Mono<List> when needed
public Mono<List<Market>> findActiveMarketsAsList() {
    return marketRepository.findByStatus(MarketStatus.ACTIVE)
        .collectList();
}
```

## File Organization

### CQRS + Hexagonal Architecture (Recommended)

CQRS (Command Query Responsibility Segregation) separates write operations (Commands) from read operations (Queries) for
better scalability and maintainability.

```
src/main/java/com/example/marketservice/
├── MarketServiceApplication.java
│
├── command/                              # WRITE SIDE (Commands)
│   ├── api/                              # Command API Layer
│   │   ├── controller/
│   │   │   └── MarketCommandController.java
│   │   └── dto/
│   │       ├── CreateMarketCommand.java
│   │       └── UpdateMarketCommand.java
│   ├── handler/                          # Command Handlers
│   │   ├── CreateMarketHandler.java
│   │   ├── UpdateMarketHandler.java
│   │   └── DeleteMarketHandler.java
│   ├── aggregate/                        # Domain Aggregates
│   │   └── MarketAggregate.java
│   └── event/                            # Domain Events
│       ├── MarketCreatedEvent.java
│       ├── MarketUpdatedEvent.java
│       └── MarketDeletedEvent.java
│
├── query/                                # READ SIDE (Queries)
│   ├── api/                              # Query API Layer
│   │   ├── controller/
│   │   │   └── MarketQueryController.java
│   │   └── dto/
│   │       ├── MarketResponse.java
│   │       ├── MarketDetailResponse.java
│   │       └── MarketListResponse.java
│   ├── handler/                          # Query Handlers
│   │   ├── GetMarketHandler.java
│   │   ├── ListMarketsHandler.java
│   │   └── SearchMarketsHandler.java
│   ├── projection/                       # Read Models (Projections)
│   │   ├── MarketReadModel.java
│   │   └── MarketSummaryProjection.java
│   └── repository/                       # Query Repositories
│       └── MarketQueryRepository.java
│
├── domain/                               # SHARED DOMAIN
│   ├── model/
│   │   ├── Market.java                   # Domain Entity
│   │   ├── MarketId.java                 # Value Object
│   │   └── MarketStatus.java             # Enum
│   ├── exception/
│   │   ├── MarketNotFoundException.java
│   │   └── InvalidMarketStateException.java
│   └── policy/                           # Domain Policies/Rules
│       └── MarketValidationPolicy.java
│
├── shared/                               # SHARED/COMMON
│   ├── cqrs/                             # CQRS Infrastructure
│   │   ├── Command.java                  # Command marker interface
│   │   ├── CommandHandler.java           # Command handler interface
│   │   ├── Query.java                    # Query marker interface
│   │   ├── QueryHandler.java             # Query handler interface
│   │   └── CommandBus.java               # Command dispatcher
│   └── event/                            # Event Infrastructure
│       ├── DomainEvent.java
│       └── EventPublisher.java
│
└── infrastructure/                       # INFRASTRUCTURE LAYER
    ├── config/
    │   ├── DatabaseConfig.java
    │   ├── RedisConfig.java
    │   ├── KafkaConfig.java
    │   └── CqrsConfig.java
    ├── persistence/
    │   ├── entity/
    │   │   └── MarketEntity.java
    │   ├── repository/
    │   │   ├── MarketWriteRepository.java   # For Commands
    │   │   └── MarketReadRepository.java    # For Queries (optimized)
    │   └── mapper/
    │       └── MarketEntityMapper.java
    ├── messaging/
    │   ├── producer/
    │   │   └── MarketEventProducer.java
    │   └── consumer/
    │       └── MarketEventConsumer.java
    ├── cache/
    │   └── MarketCacheAdapter.java
    └── external/
        └── PaymentApiClient.java
```

### Package Naming (CQRS Style)

```
# Commands (Write)
com.example.marketservice.command.api.controller.MarketCommandController
com.example.marketservice.command.api.dto.CreateMarketCommand
com.example.marketservice.command.handler.CreateMarketHandler
com.example.marketservice.command.aggregate.MarketAggregate
com.example.marketservice.command.event.MarketCreatedEvent

# Queries (Read)
com.example.marketservice.query.api.controller.MarketQueryController
com.example.marketservice.query.api.dto.MarketResponse
com.example.marketservice.query.handler.GetMarketHandler
com.example.marketservice.query.projection.MarketReadModel
com.example.marketservice.query.repository.MarketQueryRepository

# Domain (Shared)
com.example.marketservice.domain.model.Market
com.example.marketservice.domain.exception.MarketNotFoundException

# Infrastructure
com.example.marketservice.infrastructure.persistence.MarketWriteRepository
com.example.marketservice.infrastructure.persistence.MarketReadRepository
```

### Key CQRS Principles

1. **Separate Controllers**: `MarketCommandController` for mutations, `MarketQueryController` for reads
2. **Separate Repositories**: `MarketWriteRepository` for commands (full entity), `MarketReadRepository` for queries (
   projections)
3. **Command Handlers**: One handler per command, validates and executes business logic
4. **Query Handlers**: One handler per query, optimized for read performance
5. **Domain Events**: Commands emit events, consumed by query side to update projections

## Comments & Documentation

### When to Comment

```java
// GOOD: Explain WHY, not WHAT
// Use exponential backoff to avoid overwhelming the API during outages
long delay = Math.min(1000 * (long) Math.pow(2, retryCount), 30000);

// Deliberately bypassing cache here for real-time consistency
Market market = marketRepository.findByIdNoCache(marketId);

// BAD: Stating the obvious
// Increment counter by 1
count++;

// Set name to user's name
name = user.getName();
```

### JavaDoc for Public APIs

```java
/**
 * Searches markets using semantic similarity.
 *
 * <p>Uses vector embeddings stored in Redis to find markets
 * semantically similar to the query, then fetches full market
 * data from PostgreSQL.</p>
 *
 * @param query Natural language search query
 * @param limit Maximum number of results (default: 10)
 * @return Flux of markets sorted by similarity score
 * @throws RedisUnavailableException if Redis connection fails
 * @throws IllegalArgumentException if query is blank
 *
 * @see MarketRepository#findByIds(List)
 */
public Flux<Market> searchMarkets(String query, int limit) {
    // Implementation
}
```

## Database Queries

### R2DBC Best Practices

```java
// GOOD: Select only needed columns
@Query("SELECT id, name, status, volume FROM markets WHERE status = :status")
Flux<MarketSummary> findSummariesByStatus(MarketStatus status);

// GOOD: Use projections
public interface MarketSummary {
    String getId();
    String getName();
    MarketStatus getStatus();
    BigDecimal getVolume();
}

// BAD: Select everything
@Query("SELECT * FROM markets")
Flux<Market> findAll();
```

### Avoiding N+1 Queries

```java
// BAD: N+1 query problem
public Flux<MarketWithCreator> findMarketsWithCreators() {
    return marketRepository.findAll()
        .flatMap(market -> userRepository.findById(market.creatorId()) // N queries!
            .map(user -> new MarketWithCreator(market, user)));
}

// GOOD: Batch fetch with join or separate query
public Flux<MarketWithCreator> findMarketsWithCreators() {
    return marketRepository.findAllWithCreators(); // Single JOIN query
}

// Or batch fetch approach
public Mono<List<MarketWithCreator>> findMarketsWithCreators() {
    return marketRepository.findAll().collectList()
        .flatMap(markets -> {
            Set<String> creatorIds = markets.stream()
                .map(Market::creatorId)
                .collect(Collectors.toSet());
            return userRepository.findAllById(creatorIds).collectMap(User::id)
                .map(userMap -> markets.stream()
                    .map(m -> new MarketWithCreator(m, userMap.get(m.creatorId())))
                    .toList());
        });
}
```

## Code Smell Detection

Watch for these anti-patterns:

### 1. Long Methods

```java
// BAD: Method > 30 lines
public Mono<Order> processOrder(CreateOrderRequest request) {
    // 100 lines of code
}

// GOOD: Split into smaller methods
public Mono<Order> processOrder(CreateOrderRequest request) {
    return validateRequest(request)
        .then(calculateTotals(request))
        .flatMap(this::reserveInventory)
        .flatMap(this::createOrder)
        .flatMap(this::sendConfirmation);
}
```

### 2. Deep Nesting

```java
// BAD: 4+ levels of nesting
if (user != null) {
    if (user.isAdmin()) {
        if (market != null) {
            if (market.isActive()) {
                if (hasPermission) {
                    // Do something
                }
            }
        }
    }
}

// GOOD: Early returns / guard clauses
if (user == null) return Mono.error(new UnauthorizedException());
if (!user.isAdmin()) return Mono.error(new ForbiddenException());
if (market == null) return Mono.error(new NotFoundException());
if (!market.isActive()) return Mono.error(new InvalidStateException());
if (!hasPermission) return Mono.error(new ForbiddenException());

// Do something
```

### 3. Magic Numbers

```java
// BAD: Unexplained numbers
if (retryCount > 3) { }
Thread.sleep(500);

// GOOD: Named constants
private static final int MAX_RETRIES = 3;
private static final Duration DEBOUNCE_DELAY = Duration.ofMillis(500);

if (retryCount > MAX_RETRIES) { }
Mono.delay(DEBOUNCE_DELAY);
```

### 4. God Classes

```java
// BAD: Service doing everything
public class MarketService {
    public Mono<Market> create(...) { }
    public Mono<Market> update(...) { }
    public Mono<Void> delete(...) { }
    public Mono<Payment> processPayment(...) { }  // Wrong place!
    public Mono<Email> sendNotification(...) { }  // Wrong place!
    public void generateReport(...) { }           // Wrong place!
}

// GOOD: Single responsibility
public class MarketService { /* CRUD only */ }
public class PaymentService { /* Payments only */ }
public class NotificationService { /* Notifications only */ }
public class ReportService { /* Reports only */ }
```

## Code Quality Checklist

Before any commit, verify:

- [ ] All methods < 30 lines
- [ ] All classes < 400 lines
- [ ] Nesting depth < 4 levels
- [ ] No hardcoded values (use constants)
- [ ] All public APIs have JavaDoc
- [ ] Proper error handling (no empty catch blocks)
- [ ] Input validation on all endpoints
- [ ] No mutable state in reactive chains
- [ ] Tests written for new code
- [ ] No TODO comments left behind
- [ ] Logging at appropriate levels
- [ ] No sensitive data in logs

---

**Remember**: Code quality is not negotiable. Clear, maintainable code enables rapid development and confident
refactoring.
