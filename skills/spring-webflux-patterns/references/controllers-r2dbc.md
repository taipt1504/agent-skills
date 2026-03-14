# Controllers & R2DBC Reference

Annotated controllers, router functions, R2DBC patterns, and reactive transactions.

## Table of Contents
- [Annotated Controllers](#annotated-controllers)
- [Router Functions (Functional Style)](#router-functions-functional-style)
- [R2DBC Repository](#r2dbc-repository)
- [R2DBC DatabaseClient (Custom Queries)](#r2dbc-databaseclient-custom-queries)
- [Reactive Transactions](#reactive-transactions)
- [Request Validation](#request-validation)
- [Response Patterns](#response-patterns)

---

## Annotated Controllers

```java
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {
    private final UserService userService;

    @GetMapping("/{id}")
    public Mono<ResponseEntity<UserResponse>> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @GetMapping
    public Flux<UserResponse> listUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return userService.findAll(PageRequest.of(page, size));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserResponse> createUser(@Valid @RequestBody CreateUserRequest request) {
        return userService.create(request);
    }

    @PutMapping("/{id}")
    public Mono<UserResponse> updateUser(@PathVariable Long id,
                                          @Valid @RequestBody UpdateUserRequest request) {
        return userService.update(id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteUser(@PathVariable Long id) {
        return userService.delete(id);
    }

    // SSE endpoint
    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<UserEvent> streamUserEvents() {
        return userService.streamEvents();
    }
}
```

---

## Router Functions (Functional Style)

Use for fine-grained control, middleware composition, or programmatic route registration.

```java
@Configuration
public class UserRouter {
    @Bean
    public RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .GET("/api/users/{id}", handler::getUser)
            .GET("/api/users", handler::listUsers)
            .POST("/api/users", handler::createUser)
            .PUT("/api/users/{id}", handler::updateUser)
            .DELETE("/api/users/{id}", handler::deleteUser)
            .build();
    }
}

@Component
@RequiredArgsConstructor
public class UserHandler {
    private final UserService userService;
    private final Validator validator;

    public Mono<ServerResponse> getUser(ServerRequest request) {
        Long id = Long.valueOf(request.pathVariable("id"));
        return userService.findById(id)
            .flatMap(user -> ServerResponse.ok().bodyValue(user))
            .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> createUser(ServerRequest request) {
        return request.bodyToMono(CreateUserRequest.class)
            .doOnNext(dto -> {
                var errors = new BeanPropertyBindingResult(dto, "dto");
                validator.validate(dto, errors);
                if (errors.hasErrors()) throw new ServerWebInputException(errors.toString());
            })
            .flatMap(userService::create)
            .flatMap(created -> ServerResponse.created(
                URI.create("/api/users/" + created.id()))
                .bodyValue(created));
    }
}
```

---

## R2DBC Repository

```java
public interface UserRepository extends ReactiveCrudRepository<UserEntity, Long> {
    // Derived queries
    Flux<UserEntity> findByStatus(UserStatus status);
    Mono<UserEntity> findByEmail(String email);
    Flux<UserEntity> findByCreatedAtAfter(Instant since);

    // Custom @Query
    @Query("SELECT * FROM users WHERE status = :status ORDER BY created_at DESC LIMIT :limit")
    Flux<UserEntity> findActiveUsersLimited(String status, int limit);

    @Query("UPDATE users SET status = :status WHERE id = :id")
    @Modifying
    Mono<Integer> updateStatus(Long id, String status);

    // Pageable support
    Flux<UserEntity> findAllByStatus(UserStatus status, Pageable pageable);
    Mono<Long> countByStatus(UserStatus status);
}

// Entity
@Table("users")
public class UserEntity {
    @Id
    private Long id;
    private String email;
    private String name;
    @Column("status")
    private String status;
    private Instant createdAt;
    private Instant updatedAt;
}
```

---

## R2DBC DatabaseClient (Custom Queries)

Use for complex joins, dynamic queries, or when repositories don't suffice.

```java
@Repository
@RequiredArgsConstructor
public class UserQueryRepository {
    private final DatabaseClient db;

    public Flux<UserWithOrdersDto> findUsersWithOrderCount(UserStatus status) {
        return db.sql("""
                SELECT u.id, u.email, u.name, COUNT(o.id) as order_count
                FROM users u
                LEFT JOIN orders o ON o.customer_id = u.id
                WHERE u.status = :status
                GROUP BY u.id, u.email, u.name
                ORDER BY order_count DESC
                """)
            .bind("status", status.name())
            .map(row -> new UserWithOrdersDto(
                row.get("id", Long.class),
                row.get("email", String.class),
                row.get("name", String.class),
                row.get("order_count", Long.class)
            ))
            .all();
    }

    public Mono<Integer> batchUpdateStatus(List<Long> ids, UserStatus newStatus) {
        return db.sql("UPDATE users SET status = :status WHERE id IN (:ids)")
            .bind("status", newStatus.name())
            .bind("ids", ids)
            .fetch()
            .rowsUpdated()
            .map(Long::intValue);
    }

    // Dynamic query builder
    public Flux<UserEntity> search(String email, UserStatus status, int limit) {
        var query = new StringBuilder("SELECT * FROM users WHERE 1=1");
        var params = new HashMap<String, Object>();
        if (email != null) {
            query.append(" AND email LIKE :email");
            params.put("email", "%" + email + "%");
        }
        if (status != null) {
            query.append(" AND status = :status");
            params.put("status", status.name());
        }
        query.append(" LIMIT :limit");
        params.put("limit", limit);

        var spec = db.sql(query.toString());
        for (var entry : params.entrySet()) {
            spec = spec.bind(entry.getKey(), entry.getValue());
        }
        return spec.mapProperties(UserEntity.class).all();
    }
}
```

---

## Reactive Transactions

```java
@Service @RequiredArgsConstructor
public class OrderService {
    private final OrderRepository orderRepository;
    private final InventoryRepository inventoryRepository;
    private final ReactiveTransactionManager transactionManager;

    // Declarative — simplest approach
    @Transactional
    public Mono<Order> createOrder(CreateOrderCommand cmd) {
        return orderRepository.save(toEntity(cmd))
            .flatMap(order -> inventoryRepository.decrementStock(
                cmd.productId(), cmd.quantity())
                .thenReturn(order));
    }

    // Programmatic — when fine-grained control is needed
    public Mono<Order> transferStock(Long fromProductId, Long toProductId, int qty) {
        TransactionalOperator txOp = TransactionalOperator.create(transactionManager);
        return inventoryRepository.decrementStock(fromProductId, qty)
            .then(inventoryRepository.incrementStock(toProductId, qty))
            .then(orderRepository.logTransfer(fromProductId, toProductId, qty))
            .as(txOp::transactional);  // ← wraps entire chain in transaction
    }
}
```

> **Transaction rules:**
> - `@Transactional` works on `public` methods of Spring-managed beans
> - Use `TransactionalOperator` for programmatic or cross-service transactions
> - Never use `block()` inside a transaction — it will deadlock

---

## Request Validation

```java
public record CreateUserRequest(
    @NotBlank @Email String email,
    @NotBlank @Size(min = 2, max = 100) String name,
    @NotNull UserRole role
) {}

// Enable in WebFlux via @Valid on @RequestBody — Spring auto-validates
// Validation errors throw WebExchangeBindException → 400 Bad Request

// Custom validator
@Component
public class UniqueEmailValidator {
    private final UserRepository userRepository;

    public Mono<Void> validate(String email) {
        return userRepository.findByEmail(email)
            .flatMap(existing -> Mono.<Void>error(
                new DuplicateEmailException("Email already registered: " + email)))
            .then();
    }
}
```

---

## Response Patterns

```java
// Paginated response
public record PageResponse<T>(
    List<T> content,
    int page,
    int size,
    long totalElements
) {
    public static <T> Mono<PageResponse<T>> of(Flux<T> content, Mono<Long> count,
                                                int page, int size) {
        return Mono.zip(content.collectList(), count,
            (items, total) -> new PageResponse<>(items, page, size, total));
    }
}

// Usage
public Mono<PageResponse<UserResponse>> listUsers(int page, int size) {
    var pageable = PageRequest.of(page, size);
    return PageResponse.of(
        userRepository.findAll(pageable).map(this::toResponse),
        userRepository.count(),
        page, size
    );
}

// Problem Details (RFC 7807) — Spring 6+ native support
// Throw ResponseStatusException or custom exceptions handled by GlobalErrorHandler
// Returns: { "type": "...", "title": "...", "status": 404, "detail": "..." }
```
