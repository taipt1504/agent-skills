# Project Structure Reference

CQRS + Hexagonal package layout, naming conventions, JavaDoc examples, and database projection patterns.

## Table of Contents
- [CQRS + Hexagonal Directory Tree](#cqrs--hexagonal-directory-tree)
- [Package Naming Conventions](#package-naming-conventions)
- [Key CQRS Principles](#key-cqrs-principles)
- [JavaDoc for Public APIs](#javadoc-for-public-apis)
- [Database Projection Patterns](#database-projection-patterns)

---

## CQRS + Hexagonal Directory Tree

```
src/main/java/com/example/marketservice/
├── MarketServiceApplication.java
│
├── command/                              # WRITE SIDE (Commands)
│   ├── api/
│   │   ├── controller/
│   │   │   └── MarketCommandController.java
│   │   └── dto/
│   │       ├── CreateMarketCommand.java
│   │       └── UpdateMarketCommand.java
│   ├── handler/
│   │   ├── CreateMarketHandler.java
│   │   ├── UpdateMarketHandler.java
│   │   └── DeleteMarketHandler.java
│   ├── aggregate/
│   │   └── MarketAggregate.java
│   └── event/
│       ├── MarketCreatedEvent.java
│       ├── MarketUpdatedEvent.java
│       └── MarketDeletedEvent.java
│
├── query/                                # READ SIDE (Queries)
│   ├── api/
│   │   ├── controller/
│   │   │   └── MarketQueryController.java
│   │   └── dto/
│   │       ├── MarketResponse.java
│   │       ├── MarketDetailResponse.java
│   │       └── MarketListResponse.java
│   ├── handler/
│   │   ├── GetMarketHandler.java
│   │   ├── ListMarketsHandler.java
│   │   └── SearchMarketsHandler.java
│   ├── projection/
│   │   ├── MarketReadModel.java
│   │   └── MarketSummaryProjection.java
│   └── repository/
│       └── MarketQueryRepository.java
│
├── domain/                               # SHARED DOMAIN
│   ├── model/
│   │   ├── Market.java                   # Domain Entity
│   │   ├── MarketId.java                 # Value Object
│   │   └── MarketStatus.java
│   ├── exception/
│   │   ├── MarketNotFoundException.java
│   │   └── InvalidMarketStateException.java
│   └── policy/
│       └── MarketValidationPolicy.java
│
├── shared/                               # CQRS Infrastructure
│   ├── cqrs/
│   │   ├── Command.java
│   │   ├── CommandHandler.java
│   │   ├── Query.java
│   │   ├── QueryHandler.java
│   │   └── CommandBus.java
│   └── event/
│       ├── DomainEvent.java
│       └── EventPublisher.java
│
└── infrastructure/
    ├── config/
    │   ├── DatabaseConfig.java
    │   ├── RedisConfig.java
    │   ├── KafkaConfig.java
    │   └── SecurityConfig.java
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

---

## Package Naming Conventions

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

---

## Key CQRS Principles

1. **Separate Controllers** — `MarketCommandController` for mutations, `MarketQueryController` for reads
2. **Separate Repositories** — `MarketWriteRepository` for commands (full entity), `MarketReadRepository` for queries (projections)
3. **Command Handlers** — One handler per command, validates and executes business logic
4. **Query Handlers** — One handler per query, optimized for read performance
5. **Domain Events** — Commands emit events, consumed by query side to update projections

---

## JavaDoc for Public APIs

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
public Flux<Market> searchMarkets(String query, int limit) { ... }
```

Guidelines:
- Always document public API methods (services, controllers, ports)
- Explain **what** the method does and any non-obvious behavior
- Document exceptions that callers should handle
- Skip JavaDoc for trivial getters, setters, or self-documenting private methods

---

## Database Projection Patterns

### Projection Interface (R2DBC)

```java
// Only fetch columns you need — avoid SELECT *
public interface MarketSummary {
    String getId();
    String getName();
    MarketStatus getStatus();
    BigDecimal getVolume();
}

@Query("SELECT id, name, status, volume FROM markets WHERE status = :status")
Flux<MarketSummary> findSummariesByStatus(MarketStatus status);
```

### Batch Fetch to Avoid N+1

```java
// Batch fetch + correlate in memory
public Mono<List<MarketWithCreator>> findMarketsWithCreators() {
    return marketRepository.findAll().collectList()
        .flatMap(markets -> {
            var creatorIds = markets.stream().map(Market::creatorId).collect(Collectors.toSet());
            return userRepository.findAllById(creatorIds)
                .collectMap(User::id)
                .map(userMap -> markets.stream()
                    .map(m -> new MarketWithCreator(m, userMap.get(m.creatorId())))
                    .toList());
        });
}

// Or single JOIN query
@Query("SELECT m.*, u.email as creator_email FROM markets m JOIN users u ON u.id = m.creator_id")
Flux<MarketWithCreatorProjection> findAllWithCreators();
```

### Custom Validator

```java
@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = ValidSlugValidator.class)
public @interface ValidSlug {
    String message() default "Invalid slug format (lowercase letters, digits, hyphens only)";
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
