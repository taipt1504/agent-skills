---
name: backend-patterns
description: Backend architecture patterns, API design, database optimization, messaging, and server-side best practices for Java Spring WebFlux/MVC applications.
---

# Backend Development Patterns

Backend architecture patterns and best practices for scalable Java Spring applications.

## API Design Patterns

### RESTful API Structure

```java
// Resource-based URLs
GET    /api/markets                 # List resources
GET    /api/markets/{id}            # Get single resource
POST   /api/markets                 # Create resource
PUT    /api/markets/{id}            # Replace resource
PATCH  /api/markets/{id}            # Update resource
DELETE /api/markets/{id}            # Delete resource

// Query parameters for filtering, sorting, pagination
GET /api/markets?status=active&sort=volume,desc&page=0&size=20
```

### Controller Pattern (WebFlux)

```java
@RestController
@RequestMapping("/api/markets")
@RequiredArgsConstructor
@Validated
@Slf4j
public class MarketController {

    private final MarketService marketService;
    private final MarketMapper mapper;

    @GetMapping
    public Flux<MarketResponse> list(
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size,
            @RequestParam(required = false) MarketStatus status) {
        return marketService.findAll(page, size, status)
            .map(mapper::toResponse);
    }

    @GetMapping("/{id}")
    public Mono<ResponseEntity<MarketResponse>> getById(@PathVariable String id) {
        return marketService.findById(id)
            .map(mapper::toResponse)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<MarketResponse> create(@Valid @RequestBody CreateMarketRequest request) {
        return marketService.create(mapper.toDomain(request))
            .map(mapper::toResponse);
    }

    @PatchMapping("/{id}")
    public Mono<MarketResponse> update(
            @PathVariable String id,
            @Valid @RequestBody UpdateMarketRequest request) {
        return marketService.update(id, mapper.toDomain(request))
            .map(mapper::toResponse);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> delete(@PathVariable String id) {
        return marketService.delete(id);
    }
}
```

### Controller Pattern (Spring MVC)

```java
@RestController
@RequestMapping("/api/markets")
@RequiredArgsConstructor
@Validated
@Slf4j
public class MarketController {

    private final MarketService marketService;
    private final MarketMapper mapper;

    @GetMapping
    public Page<MarketResponse> list(
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size,
            @RequestParam(required = false) MarketStatus status) {
        Pageable pageable = PageRequest.of(page, size);
        return marketService.findAll(status, pageable)
            .map(mapper::toResponse);
    }

    @GetMapping("/{id}")
    public ResponseEntity<MarketResponse> getById(@PathVariable String id) {
        return marketService.findById(id)
            .map(mapper::toResponse)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public MarketResponse create(@Valid @RequestBody CreateMarketRequest request) {
        Market market = marketService.create(mapper.toDomain(request));
        return mapper.toResponse(market);
    }
}
```

### Response Format

```java
// Standard API response wrapper
public record ApiResponse<T>(
    boolean success,
    T data,
    String error,
    PageInfo pageInfo
) {
    public static <T> ApiResponse<T> ok(T data) {
        return new ApiResponse<>(true, data, null, null);
    }

    public static <T> ApiResponse<T> ok(T data, PageInfo pageInfo) {
        return new ApiResponse<>(true, data, null, pageInfo);
    }

    public static <T> ApiResponse<T> error(String message) {
        return new ApiResponse<>(false, null, message, null);
    }
}

public record PageInfo(
    int page,
    int size,
    long totalElements,
    int totalPages
) {
    public static PageInfo from(Page<?> page) {
        return new PageInfo(
            page.getNumber(),
            page.getSize(),
            page.getTotalElements(),
            page.getTotalPages()
        );
    }
}
```

## CQRS Pattern

CQRS (Command Query Responsibility Segregation) separates write operations (Commands) from read operations (Queries) for
better scalability and maintainability.

### File Structure (CQRS)

```
src/main/java/com/example/marketservice/
├── command/                              # WRITE SIDE
│   ├── api/controller/MarketCommandController.java
│   ├── dto/
│   │   ├── CreateMarketCommand.java
│   │   └── UpdateMarketCommand.java
│   ├── handler/
│   │   ├── CreateMarketHandler.java
│   │   └── UpdateMarketHandler.java
│   ├── aggregate/MarketAggregate.java
│   └── event/MarketCreatedEvent.java
│
├── query/                                # READ SIDE
│   ├── api/controller/MarketQueryController.java
│   ├── dto/MarketResponse.java
│   ├── handler/
│   │   ├── GetMarketHandler.java
│   │   └── ListMarketsHandler.java
│   ├── projection/MarketReadModel.java
│   └── repository/MarketQueryRepository.java
│
├── domain/                               # SHARED
│   └── model/Market.java
│
├── shared/cqrs/                          # CQRS Infrastructure
│   ├── Command.java
│   ├── CommandHandler.java
│   ├── Query.java
│   └── QueryHandler.java
│
└── infrastructure/
    └── persistence/
        ├── MarketWriteRepository.java
        └── MarketReadRepository.java
```

### Command (Write Side)

```java
// Command DTO
public record CreateMarketCommand(
    @NotBlank String name,
    @NotBlank String description,
    @NotNull @Future Instant endDate
) implements Command {}

// Command Handler
@Component
@RequiredArgsConstructor
@Slf4j
public class CreateMarketHandler implements CommandHandler<CreateMarketCommand, Market> {

    private final MarketWriteRepository repository;
    private final EventPublisher eventPublisher;

    @Override
    @Transactional
    public Mono<Market> handle(CreateMarketCommand command) {
        Market market = Market.builder()
            .id(UUID.randomUUID().toString())
            .name(command.name())
            .description(command.description())
            .endDate(command.endDate())
            .status(MarketStatus.PENDING)
            .createdAt(Instant.now())
            .build();

        return repository.save(market)
            .doOnSuccess(saved -> {
                log.info("Market created: id={}", saved.id());
                eventPublisher.publish(new MarketCreatedEvent(saved.id(), saved.name()));
            });
    }
}

// Command Controller
@RestController
@RequestMapping("/api/markets")
@RequiredArgsConstructor
public class MarketCommandController {

    private final CreateMarketHandler createHandler;
    private final UpdateMarketHandler updateHandler;
    private final DeleteMarketHandler deleteHandler;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<MarketResponse> create(@Valid @RequestBody CreateMarketCommand command) {
        return createHandler.handle(command)
            .map(MarketResponse::from);
    }

    @PutMapping("/{id}")
    public Mono<MarketResponse> update(
            @PathVariable String id,
            @Valid @RequestBody UpdateMarketCommand command) {
        return updateHandler.handle(id, command)
            .map(MarketResponse::from);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> delete(@PathVariable String id) {
        return deleteHandler.handle(id);
    }
}
```

### Query (Read Side)

```java
// Query DTO
public record GetMarketQuery(String id) implements Query<MarketDetailResponse> {}

public record ListMarketsQuery(
    int page,
    int size,
    MarketStatus status
) implements Query<Page<MarketResponse>> {}

// Query Handler
@Component
@RequiredArgsConstructor
public class GetMarketHandler implements QueryHandler<GetMarketQuery, MarketDetailResponse> {

    private final MarketQueryRepository queryRepository;
    private final MarketCacheAdapter cache;

    @Override
    public Mono<MarketDetailResponse> handle(GetMarketQuery query) {
        return cache.get(query.id())
            .switchIfEmpty(
                queryRepository.findById(query.id())
                    .flatMap(market -> cache.put(query.id(), market)
                        .thenReturn(market))
            )
            .map(MarketDetailResponse::from)
            .switchIfEmpty(Mono.error(new MarketNotFoundException(query.id())));
    }
}

@Component
@RequiredArgsConstructor
public class ListMarketsHandler implements QueryHandler<ListMarketsQuery, Page<MarketResponse>> {

    private final MarketQueryRepository queryRepository;

    @Override
    public Mono<Page<MarketResponse>> handle(ListMarketsQuery query) {
        return queryRepository.findAll(query.status(), query.page(), query.size())
            .map(page -> page.map(MarketResponse::from));
    }
}

// Query Controller
@RestController
@RequestMapping("/api/markets")
@RequiredArgsConstructor
public class MarketQueryController {

    private final GetMarketHandler getHandler;
    private final ListMarketsHandler listHandler;
    private final SearchMarketsHandler searchHandler;

    @GetMapping("/{id}")
    public Mono<MarketDetailResponse> getById(@PathVariable String id) {
        return getHandler.handle(new GetMarketQuery(id));
    }

    @GetMapping
    public Mono<Page<MarketResponse>> list(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) MarketStatus status) {
        return listHandler.handle(new ListMarketsQuery(page, size, status));
    }

    @GetMapping("/search")
    public Flux<MarketResponse> search(
            @RequestParam String q,
            @RequestParam(defaultValue = "10") int limit) {
        return searchHandler.handle(new SearchMarketsQuery(q, limit));
    }
}
```

### CQRS Infrastructure

```java
// Marker Interfaces
public interface Command {}

public interface Query<R> {}

@FunctionalInterface
public interface CommandHandler<C extends Command, R> {
    Mono<R> handle(C command);
}

@FunctionalInterface
public interface QueryHandler<Q extends Query<R>, R> {
    Mono<R> handle(Q query);
}

// Command Bus (Optional - for decoupling)
@Component
@RequiredArgsConstructor
public class CommandBus {

    private final ApplicationContext context;

    @SuppressWarnings("unchecked")
    public <C extends Command, R> Mono<R> dispatch(C command) {
        String handlerName = command.getClass().getSimpleName()
            .replace("Command", "Handler");
        handlerName = Character.toLowerCase(handlerName.charAt(0)) + handlerName.substring(1);
        
        CommandHandler<C, R> handler = (CommandHandler<C, R>) 
            context.getBean(handlerName, CommandHandler.class);
        return handler.handle(command);
    }
}

// Query Bus
@Component
@RequiredArgsConstructor
public class QueryBus {

    private final ApplicationContext context;

    @SuppressWarnings("unchecked")
    public <Q extends Query<R>, R> Mono<R> dispatch(Q query) {
        String handlerName = query.getClass().getSimpleName()
            .replace("Query", "Handler");
        handlerName = Character.toLowerCase(handlerName.charAt(0)) + handlerName.substring(1);
        
        QueryHandler<Q, R> handler = (QueryHandler<Q, R>) 
            context.getBean(handlerName, QueryHandler.class);
        return handler.handle(query);
    }
}
```

### Separate Repositories

```java
// Write Repository (for Commands) - Full entity operations
public interface MarketWriteRepository {
    Mono<Market> save(Market market);
    Mono<Market> findById(String id);
    Mono<Void> deleteById(String id);
}

@Repository
@RequiredArgsConstructor
public class MarketWriteRepositoryImpl implements MarketWriteRepository {

    private final MarketR2dbcRepository r2dbcRepo;
    private final MarketEntityMapper mapper;

    @Override
    public Mono<Market> save(Market market) {
        return r2dbcRepo.save(mapper.toEntity(market))
            .map(mapper::toDomain);
    }
}

// Read Repository (for Queries) - Optimized projections
public interface MarketQueryRepository {
    Mono<MarketReadModel> findById(String id);
    Mono<Page<MarketSummary>> findAll(MarketStatus status, int page, int size);
    Flux<MarketSummary> search(String query, int limit);
}

@Repository
@RequiredArgsConstructor
public class MarketQueryRepositoryImpl implements MarketQueryRepository {

    private final DatabaseClient databaseClient;

    @Override
    public Mono<MarketReadModel> findById(String id) {
        return databaseClient.sql("""
            SELECT m.*, u.name as creator_name
            FROM markets m
            LEFT JOIN users u ON m.creator_id = u.id
            WHERE m.id = :id
            """)
            .bind("id", id)
            .map(this::mapToReadModel)
            .one();
    }

    @Override
    public Flux<MarketSummary> search(String query, int limit) {
        return databaseClient.sql("""
            SELECT id, name, status, volume
            FROM markets
            WHERE name ILIKE :pattern OR description ILIKE :pattern
            ORDER BY volume DESC
            LIMIT :limit
            """)
            .bind("pattern", "%" + query + "%")
            .bind("limit", limit)
            .map(this::mapToSummary)
            .all();
    }
}
```

### Domain Events (Event Sourcing Ready)

```java
// Base Event
public abstract class DomainEvent {
    private final String eventId = UUID.randomUUID().toString();
    private final Instant occurredAt = Instant.now();

    public String getEventId() { return eventId; }
    public Instant getOccurredAt() { return occurredAt; }
}

// Market Events
public class MarketCreatedEvent extends DomainEvent {
    private final String marketId;
    private final String name;
    private final String description;

    public MarketCreatedEvent(String marketId, String name, String description) {
        this.marketId = marketId;
        this.name = name;
        this.description = description;
    }
    // getters
}

public class MarketUpdatedEvent extends DomainEvent {
    private final String marketId;
    private final Map<String, Object> changes;
    // constructor, getters
}

// Event Publisher
@Component
@RequiredArgsConstructor
public class EventPublisher {

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;
    private final ApplicationEventPublisher springEventPublisher;

    public void publish(DomainEvent event) {
        // Publish to Kafka for external consumers
        try {
            String payload = objectMapper.writeValueAsString(event);
            kafkaTemplate.send("domain-events", event.getEventId(), payload);
        } catch (JsonProcessingException e) {
            log.error("Failed to serialize event", e);
        }

        // Publish in-process for projections
        springEventPublisher.publishEvent(event);
    }
}

// Projection Updater (listens to events and updates read models)
@Component
@RequiredArgsConstructor
@Slf4j
public class MarketProjectionUpdater {

    private final MarketReadModelRepository readModelRepo;

    @EventListener
    public void on(MarketCreatedEvent event) {
        MarketReadModel readModel = MarketReadModel.builder()
            .id(event.getMarketId())
            .name(event.getName())
            .status(MarketStatus.PENDING)
            .createdAt(event.getOccurredAt())
            .build();

        readModelRepo.save(readModel)
            .subscribe(saved -> log.debug("Projection updated: {}", saved.id()));
    }

    @EventListener
    public void on(MarketUpdatedEvent event) {
        readModelRepo.findById(event.getMarketId())
            .map(existing -> applyChanges(existing, event.getChanges()))
            .flatMap(readModelRepo::save)
            .subscribe();
    }
}
```

```

## Database Patterns

### Query Optimization

```java
// GOOD: Select only needed columns with projection
public interface MarketSummaryProjection {
    String getId();
    String getName();
    MarketStatus getStatus();
    BigDecimal getVolume();
}

@Query("SELECT id, name, status, volume FROM markets WHERE status = :status")
Flux<MarketSummaryProjection> findSummariesByStatus(@Param("status") String status);

// GOOD: Use database-level pagination
@Query("""
    SELECT * FROM markets 
    WHERE status = :status
    ORDER BY created_at DESC
    LIMIT :limit OFFSET :offset
    """)
Flux<MarketEntity> findByStatusPaginated(
    @Param("status") String status,
    @Param("limit") int limit,
    @Param("offset") int offset
);
```

### Avoiding N+1 Queries

```java
// BAD: N+1 query problem
public Flux<MarketWithCreator> findMarketsWithCreators() {
    return marketRepository.findAll()
        .flatMap(market -> 
            userRepository.findById(market.creatorId()) // N additional queries!
                .map(user -> new MarketWithCreator(market, user))
        );
}

// GOOD: Use JOIN query
@Query("""
    SELECT m.*, u.name as creator_name, u.email as creator_email
    FROM markets m
    JOIN users u ON m.creator_id = u.id
    WHERE m.status = :status
    """)
Flux<MarketWithCreatorEntity> findMarketsWithCreators(@Param("status") String status);

// GOOD: Batch fetch with collectMap
public Mono<List<MarketWithCreator>> findMarketsWithCreators() {
    return marketRepository.findAll()
        .collectList()
        .flatMap(markets -> {
            Set<String> creatorIds = markets.stream()
                .map(Market::creatorId)
                .collect(Collectors.toSet());

            return userRepository.findAllById(creatorIds)
                .collectMap(User::id)
                .map(userMap -> markets.stream()
                    .map(m -> new MarketWithCreator(m, userMap.get(m.creatorId())))
                    .toList());
        });
}
```

### Transaction Management

```java
// Programmatic transactions with TransactionalOperator
@Service
@RequiredArgsConstructor
public class OrderService {

    private final TransactionalOperator transactionalOperator;
    private final OrderRepository orderRepository;
    private final InventoryRepository inventoryRepository;
    private final PaymentService paymentService;

    public Mono<Order> createOrder(CreateOrderCommand command) {
        return Mono.zip(
                validateInventory(command),
                processPayment(command)
            )
            .flatMap(tuple -> {
                Order order = Order.create(command);
                return orderRepository.save(order)
                    .flatMap(saved -> reserveInventory(saved)
                        .thenReturn(saved));
            })
            .as(transactionalOperator::transactional);
    }
}

// Declarative with @Transactional
@Transactional
public Mono<Order> createOrder(CreateOrderCommand command) {
    // All operations within this method are in a single transaction
    return validateInventory(command)
        .then(processPayment(command))
        .flatMap(payment -> {
            Order order = Order.create(command, payment);
            return orderRepository.save(order);
        })
        .flatMap(this::reserveInventory);
}
```

## Caching Strategies

### Redis Caching (Reactive)

```java
@Service
@RequiredArgsConstructor
public class CachedMarketService implements MarketService {

    private final MarketService delegate;
    private final ReactiveRedisTemplate<String, Market> redisTemplate;
    private final ReactiveValueOperations<String, Market> valueOps;

    private static final Duration CACHE_TTL = Duration.ofMinutes(5);

    @Override
    public Mono<Market> findById(String id) {
        String cacheKey = "market:" + id;

        return valueOps.get(cacheKey)
            .switchIfEmpty(
                delegate.findById(id)
                    .flatMap(market -> 
                        valueOps.set(cacheKey, market, CACHE_TTL)
                            .thenReturn(market)
                    )
            );
    }

    public Mono<Void> invalidateCache(String id) {
        return redisTemplate.delete("market:" + id).then();
    }
}
```

### Local Cache with Caffeine

```java
@Configuration
public class CacheConfig {

    @Bean
    public Cache<String, Market> marketCache() {
        return Caffeine.newBuilder()
            .maximumSize(1000)
            .expireAfterWrite(Duration.ofMinutes(5))
            .recordStats()
            .build();
    }
}

@Service
@RequiredArgsConstructor
public class CachedMarketService {

    private final MarketRepository repository;
    private final Cache<String, Market> cache;

    public Mono<Market> findById(String id) {
        Market cached = cache.getIfPresent(id);
        if (cached != null) {
            return Mono.just(cached);
        }

        return repository.findById(id)
            .doOnNext(market -> cache.put(id, market));
    }
}
```

### Cache-Aside with Annotations (Spring MVC)

```java
@Service
public class MarketService {

    @Cacheable(value = "markets", key = "#id")
    public Market findById(String id) {
        return marketRepository.findById(id)
            .orElseThrow(() -> new MarketNotFoundException(id));
    }

    @CachePut(value = "markets", key = "#market.id")
    public Market save(Market market) {
        return marketRepository.save(market);
    }

    @CacheEvict(value = "markets", key = "#id")
    public void delete(String id) {
        marketRepository.deleteById(id);
    }

    @CacheEvict(value = "markets", allEntries = true)
    public void clearCache() {
        // Clears all cache entries
    }
}
```

## Error Handling Patterns

### Domain Exceptions

```java
// Base exception
public abstract class DomainException extends RuntimeException {
    private final String code;

    protected DomainException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String getCode() { return code; }
}

// Specific exceptions
public class MarketNotFoundException extends DomainException {
    public MarketNotFoundException(String id) {
        super("MARKET_NOT_FOUND", "Market not found: " + id);
    }
}

public class InsufficientBalanceException extends DomainException {
    public InsufficientBalanceException(BigDecimal required, BigDecimal available) {
        super("INSUFFICIENT_BALANCE", 
            String.format("Insufficient balance: required %s, available %s", required, available));
    }
}

public class DuplicateMarketException extends DomainException {
    public DuplicateMarketException(String slug) {
        super("DUPLICATE_MARKET", "Market with slug already exists: " + slug);
    }
}
```

### Global Exception Handler

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(DomainException.class)
    public ResponseEntity<ErrorResponse> handleDomain(DomainException ex) {
        HttpStatus status = resolveStatus(ex);
        return ResponseEntity.status(status)
            .body(new ErrorResponse(ex.getCode(), ex.getMessage()));
    }

    @ExceptionHandler(WebExchangeBindException.class)
    public ResponseEntity<ErrorResponse> handleValidation(WebExchangeBindException ex) {
        String message = ex.getBindingResult().getFieldErrors().stream()
            .map(e -> e.getField() + ": " + e.getDefaultMessage())
            .collect(Collectors.joining(", "));

        return ResponseEntity.badRequest()
            .body(new ErrorResponse("VALIDATION_ERROR", message));
    }

    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<ErrorResponse> handleDatabase(DataAccessException ex) {
        log.error("Database error", ex);
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
            .body(new ErrorResponse("DATABASE_ERROR", "Service temporarily unavailable"));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(Exception ex) {
        log.error("Unexpected error", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse("INTERNAL_ERROR", "An error occurred"));
    }

    private HttpStatus resolveStatus(DomainException ex) {
        return switch (ex) {
            case MarketNotFoundException e -> HttpStatus.NOT_FOUND;
            case InsufficientBalanceException e -> HttpStatus.BAD_REQUEST;
            case DuplicateMarketException e -> HttpStatus.CONFLICT;
            default -> HttpStatus.INTERNAL_SERVER_ERROR;
        };
    }
}

public record ErrorResponse(String code, String message) {}
```

### Retry with Exponential Backoff

```java
@Service
@RequiredArgsConstructor
public class ExternalApiClient {

    private final WebClient webClient;
    private static final int MAX_RETRIES = 3;

    public Mono<ExternalData> fetchData(String id) {
        return webClient.get()
            .uri("/api/data/{id}", id)
            .retrieve()
            .bodyToMono(ExternalData.class)
            .retryWhen(Retry.backoff(MAX_RETRIES, Duration.ofSeconds(1))
                .filter(this::isRetryable)
                .doBeforeRetry(signal -> 
                    log.warn("Retrying after error: {}", signal.failure().getMessage())
                ))
            .onErrorMap(e -> new ExternalApiException("Failed to fetch data", e));
    }

    private boolean isRetryable(Throwable throwable) {
        return throwable instanceof WebClientResponseException ex
            && (ex.getStatusCode().is5xxServerError() || 
                ex.getStatusCode() == HttpStatus.TOO_MANY_REQUESTS);
    }
}
```

## Messaging Patterns

### Kafka Producer

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class MarketEventPublisher {

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final ObjectMapper objectMapper;

    private static final String TOPIC = "market-events";

    public void publish(MarketEvent event) {
        try {
            String payload = objectMapper.writeValueAsString(event);
            kafkaTemplate.send(TOPIC, event.marketId(), payload)
                .whenComplete((result, ex) -> {
                    if (ex != null) {
                        log.error("Failed to publish event: {}", event, ex);
                    } else {
                        log.debug("Published event to {}: {}", 
                            result.getRecordMetadata().topic(), event);
                    }
                });
        } catch (JsonProcessingException e) {
            log.error("Failed to serialize event: {}", event, e);
        }
    }
}
```

### Kafka Consumer

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class MarketEventConsumer {

    private final MarketService marketService;
    private final ObjectMapper objectMapper;

    @KafkaListener(topics = "market-events", groupId = "market-processor")
    public void consume(ConsumerRecord<String, String> record) {
        try {
            MarketEvent event = objectMapper.readValue(record.value(), MarketEvent.class);
            processEvent(event);
            log.debug("Processed event: {}", event);
        } catch (Exception e) {
            log.error("Failed to process message: key={}, value={}", 
                record.key(), record.value(), e);
            // Consider sending to DLQ
        }
    }

    private void processEvent(MarketEvent event) {
        switch (event) {
            case MarketCreatedEvent e -> handleMarketCreated(e);
            case MarketUpdatedEvent e -> handleMarketUpdated(e);
            case MarketDeletedEvent e -> handleMarketDeleted(e);
            default -> log.warn("Unknown event type: {}", event.getClass());
        }
    }
}
```

### Reactive Kafka

```java
@Configuration
public class ReactiveKafkaConfig {

    @Bean
    public ReactiveKafkaProducerTemplate<String, String> reactiveKafkaProducer(
            KafkaProperties properties) {
        Map<String, Object> props = properties.buildProducerProperties();
        return new ReactiveKafkaProducerTemplate<>(SenderOptions.create(props));
    }

    @Bean
    public ReactiveKafkaConsumerTemplate<String, String> reactiveKafkaConsumer(
            KafkaProperties properties) {
        Map<String, Object> props = properties.buildConsumerProperties();
        ReceiverOptions<String, String> receiverOptions = ReceiverOptions
            .<String, String>create(props)
            .subscription(List.of("market-events"));
        return new ReactiveKafkaConsumerTemplate<>(receiverOptions);
    }
}

@Service
@RequiredArgsConstructor
public class ReactiveEventPublisher {

    private final ReactiveKafkaProducerTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    public Mono<Void> publish(String topic, String key, Object event) {
        return Mono.fromCallable(() -> objectMapper.writeValueAsString(event))
            .flatMap(payload -> kafkaTemplate.send(topic, key, payload))
            .doOnSuccess(result -> log.debug("Published to {}", topic))
            .then();
    }
}
```

## Logging & Monitoring

### Structured Logging with MDC

```java
@Component
public class RequestLoggingFilter implements WebFilter {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String requestId = UUID.randomUUID().toString().substring(0, 8);

        return chain.filter(exchange)
            .contextWrite(Context.of("requestId", requestId))
            .doOnEach(signal -> {
                if (!signal.isOnComplete()) {
                    Optional.ofNullable(signal.getContextView().getOrDefault("requestId", null))
                        .map(Object::toString)
                        .ifPresent(id -> MDC.put("requestId", id));
                }
            });
    }
}

@Slf4j
@Service
public class MarketService {

    public Mono<Market> findById(String id) {
        log.info("Fetching market: id={}", id);
        return marketRepository.findById(id)
            .doOnNext(m -> log.debug("Found market: {}", m.name()))
            .doOnError(e -> log.error("Failed to fetch market: id={}", id, e));
    }
}
```

### Metrics with Micrometer

```java
@Service
@RequiredArgsConstructor
public class MarketService {

    private final MarketRepository repository;
    private final MeterRegistry meterRegistry;
    private final Timer marketSearchTimer;
    private final Counter marketCreatedCounter;

    public MarketService(MarketRepository repository, MeterRegistry meterRegistry) {
        this.repository = repository;
        this.meterRegistry = meterRegistry;
        this.marketSearchTimer = Timer.builder("market.search.time")
            .description("Time taken for market search")
            .register(meterRegistry);
        this.marketCreatedCounter = Counter.builder("market.created.count")
            .description("Number of markets created")
            .register(meterRegistry);
    }

    public Flux<Market> search(String query) {
        return Flux.defer(() -> {
            long start = System.nanoTime();
            return repository.search(query)
                .doFinally(signal -> 
                    marketSearchTimer.record(System.nanoTime() - start, TimeUnit.NANOSECONDS));
        });
    }

    public Mono<Market> create(Market market) {
        return repository.save(market)
            .doOnSuccess(m -> marketCreatedCounter.increment());
    }
}
```

## Health Checks

```java
@Component
public class DatabaseHealthIndicator extends AbstractReactiveHealthIndicator {

    private final DatabaseClient databaseClient;

    public DatabaseHealthIndicator(DatabaseClient databaseClient) {
        super("Database health check failed");
        this.databaseClient = databaseClient;
    }

    @Override
    protected Mono<Health> doHealthCheck(Health.Builder builder) {
        return databaseClient.sql("SELECT 1")
            .fetch()
            .one()
            .map(result -> builder.up()
                .withDetail("database", "PostgreSQL")
                .build())
            .onErrorResume(e -> Mono.just(builder.down(e).build()));
    }
}

@Component
public class RedisHealthIndicator extends AbstractReactiveHealthIndicator {

    private final ReactiveRedisTemplate<String, String> redisTemplate;

    @Override
    protected Mono<Health> doHealthCheck(Health.Builder builder) {
        return redisTemplate.getConnectionFactory()
            .getReactiveConnection()
            .ping()
            .map(pong -> builder.up()
                .withDetail("redis", "connected")
                .build())
            .onErrorResume(e -> Mono.just(builder.down(e).build()));
    }
}
```

---

**Remember**: Backend patterns enable scalable, maintainable server-side applications. Choose patterns that fit your
complexity level - don't over-engineer simple services.
