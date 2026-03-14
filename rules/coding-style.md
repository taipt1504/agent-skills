# Coding Style

## Immutability (CRITICAL)

ALWAYS create new objects, NEVER mutate existing state:

```java
// ❌ WRONG: Mutation
public Order updateStatus(Order order, OrderStatus status) {
    order.setStatus(status);  // MUTATION!
    return order;
}

// ✅ CORRECT: Immutability with builder/copy
public Order updateStatus(Order order, OrderStatus status) {
    return order.toBuilder()
        .status(status)
        .updatedAt(Instant.now())
        .build();
}

// ✅ CORRECT: Using Lombok @With
@Value
@Builder(toBuilder = true)
public class Order {
    String id;
    OrderStatus status;
    Instant updatedAt;
}

Order updated = order.withStatus(OrderStatus.CONFIRMED);
```

## Reactive Immutability

```java
// ❌ WRONG: Mutating in reactive chain
public Mono<Order> process(Order order) {
    return Mono.just(order)
        .map(o -> {
            o.setProcessed(true);  // MUTATION in reactive!
            return o;
        });
}

// ✅ CORRECT: Create new instance
public Mono<Order> process(Order order) {
    return Mono.just(order)
        .map(o -> o.toBuilder()
            .processed(true)
            .processedAt(Instant.now())
            .build());
}
```

## File Organization

MANY SMALL FILES > FEW LARGE FILES:

```
# Structure by feature/domain (Hexagonal)
src/main/java/com/example/
├── order/                    # Feature module
│   ├── domain/               # Domain models
│   │   ├── Order.java
│   │   ├── OrderStatus.java
│   │   └── OrderItem.java
│   ├── application/          # Use cases
│   │   ├── CreateOrderUseCase.java
│   │   └── GetOrderUseCase.java
│   ├── infrastructure/       # Adapters
│   │   ├── OrderR2dbcRepository.java
│   │   └── OrderKafkaPublisher.java
│   └── interfaces/           # Controllers
│       └── OrderController.java
```

### File Size Guidelines

- **200-400 lines**: Ideal
- **800 lines**: Maximum
- **50 lines per method**: Maximum
- **4 levels nesting**: Maximum

## Error Handling

### Reactive Error Handling

```java
// ✅ CORRECT: Comprehensive reactive error handling
public Mono<Order> createOrder(CreateOrderCommand command) {
    return validateCommand(command)
        .flatMap(this::processOrder)
        .doOnError(e -> log.error("Order creation failed: {}", command.getId(), e))
        .onErrorMap(DataAccessException.class, e -> 
            new ServiceException("Database error", e))
        .onErrorMap(ValidationException.class, e ->
            new BadRequestException(e.getMessage()));
}
```

### Exception Types

```java
// Domain exceptions
public class OrderNotFoundException extends RuntimeException {
    public OrderNotFoundException(String orderId) {
        super("Order not found: " + orderId);
    }
}

// Use specific exceptions, not generic ones
// ❌ throw new RuntimeException("Error");
// ✅ throw new OrderNotFoundException(orderId);
```

## Input Validation

### Bean Validation

```java
public class CreateOrderRequest {
    @NotBlank(message = "Customer ID is required")
    private String customerId;
    
    @NotEmpty(message = "Order must have at least one item")
    @Valid
    private List<OrderItemRequest> items;
    
    @DecimalMin(value = "0.01", message = "Amount must be positive")
    private BigDecimal amount;
    
    @Email(message = "Invalid email format")
    private String email;
}

// In controller
@PostMapping("/orders")
public Mono<Order> createOrder(@Valid @RequestBody CreateOrderRequest request) {
    return orderService.create(request);
}
```

### Custom Validators

```java
@Constraint(validatedBy = OrderIdValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidOrderId {
    String message() default "Invalid order ID format";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

public class OrderIdValidator implements ConstraintValidator<ValidOrderId, String> {
    private static final Pattern ORDER_ID_PATTERN = Pattern.compile("^ORD-[A-Z0-9]{8}$");
    
    @Override
    public boolean isValid(String value, ConstraintValidatorContext context) {
        return value != null && ORDER_ID_PATTERN.matcher(value).matches();
    }
}
```

## Naming Conventions

### Classes and Interfaces

```java
// Domain
Order, OrderItem, OrderStatus           // Entities, Value Objects
OrderCreatedEvent, OrderShippedEvent    // Domain Events
OrderRepository                         // Repository Interfaces

// Application
CreateOrderUseCase, GetOrderQuery       // Use Cases
OrderService, OrderQueryService         // Services

// Infrastructure
OrderR2dbcRepository                    // Repository Implementations
OrderKafkaPublisher                     // Message Publishers

// Interfaces
OrderController, OrderHandler           // REST Controllers
OrderEventListener                      // Event Handlers
```

### Methods

```java
// Commands (change state)
createOrder(), updateStatus(), cancelOrder()

// Queries (no side effects)
findById(), findByCustomerId(), existsById()

// Reactive
findById() → Mono<Order>
findAll() → Flux<Order>
save() → Mono<Order>
```

## Code Quality Checklist

Before marking work complete:

- [ ] Code follows immutability patterns
- [ ] Methods are small (<50 lines)
- [ ] Classes are focused (<400 lines typical, <800 max)
- [ ] No deep nesting (>4 levels)
- [ ] Proper reactive error handling (onErrorResume, onErrorMap)
- [ ] No System.out.println or printStackTrace
- [ ] No hardcoded magic numbers/strings (use constants)
- [ ] All public APIs have Javadoc
- [ ] Bean Validation on all inputs
- [ ] Lombok used appropriately (@Value, @Builder, @RequiredArgsConstructor)
- [ ] No blocking calls in reactive chains

## Anti-Patterns to Avoid

```java
// ❌ God classes with too many responsibilities
public class OrderManager {
    // 50+ methods handling orders, payments, notifications, etc.
}

// ❌ Anemic domain models
public class Order {
    private String id;
    private String status;
    // Only getters/setters, no behavior
}

// ❌ Static utility classes for everything
public class OrderUtils {
    public static Order process(Order order) { ... }
}

// ✅ Rich domain models with behavior
public class Order {
    public Order confirm() {
        if (this.status != OrderStatus.PENDING) {
            throw new IllegalStateException("Cannot confirm non-pending order");
        }
        return this.toBuilder().status(OrderStatus.CONFIRMED).build();
    }
}
```
