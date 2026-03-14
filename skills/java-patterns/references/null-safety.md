# Null Safety Patterns

## Table of Contents

- [Optional Usage](#optional-usage)
- [Null Validation](#null-validation)
- [Annotations](#annotations)
- [Null Object Pattern](#null-object-pattern)

---

## Optional Usage

### When to Use Optional

```java
// ✅ Method return values that may be absent
public Optional<User> findById(String id) {
    return Optional.ofNullable(cache.get(id));
}

// ✅ Chaining with flatMap
public Optional<String> getUserEmail(String userId) {
    return findById(userId)
        .map(User::email);
}

// ❌ Never use for fields, parameters, or collections
public class User {
    // ❌ Don't do this
    private Optional<String> middleName;
    
    // ✅ Do this instead
    private String middleName;  // null means absent
}
```

### Optional Patterns

```java
// ✅ orElseThrow with meaningful exception
User user = findById(id)
    .orElseThrow(() -> new UserNotFoundException("User not found: " + id));

// ✅ orElseGet for lazy default
User user = findById(id)
    .orElseGet(() -> createDefaultUser());

// ✅ ifPresentOrElse for side effects
findById(id).ifPresentOrElse(
    user -> log.info("Found user: {}", user.name()),
    () -> log.warn("User not found: {}", id)
);

// ✅ filter for conditional logic
Optional<User> activeUser = findById(id)
    .filter(User::isActive);

// ✅ Combining optionals
Optional<String> fullName = firstName.flatMap(fn ->
    lastName.map(ln -> fn + " " + ln)
);

// ❌ Avoid .get() without isPresent check
// ❌ Avoid using Optional.of() with nullable value
```

### Optional with Streams

```java
// ✅ Convert Optional to Stream
List<User> users = userIds.stream()
    .map(this::findById)
    .flatMap(Optional::stream)  // Filters empty and unwraps
    .toList();

// ✅ Find first present
Optional<User> firstActive = userIds.stream()
    .map(this::findById)
    .filter(Optional::isPresent)
    .map(Optional::get)
    .findFirst();
```

## Null Validation

### Objects.requireNonNull

```java
public class UserService {
    private final UserRepository repository;
    
    public UserService(UserRepository repository) {
        this.repository = Objects.requireNonNull(repository, "repository must not be null");
    }
    
    public void createUser(String name, String email) {
        Objects.requireNonNull(name, "name must not be null");
        Objects.requireNonNull(email, "email must not be null");
        // proceed with creation
    }
}
```

### Precondition Checks

```java
public record PageRequest(int page, int size) {
    public PageRequest {
        if (page < 0) throw new IllegalArgumentException("page must be >= 0");
        if (size < 1 || size > 100) throw new IllegalArgumentException("size must be 1-100");
    }
}
```

## Annotations

### Lombok @NonNull

```java
@Service
@RequiredArgsConstructor
public class OrderService {
    private final @NonNull OrderRepository repository;
    private final @NonNull EventPublisher eventPublisher;
    
    public Order create(@NonNull CreateOrderCommand command) {
        // Lombok generates null checks automatically
    }
}
```

### Bean Validation (@NotNull, @NotBlank)

```java
public record CreateUserRequest(
    @NotBlank(message = "Name is required")
    String name,
    
    @NotNull(message = "Email is required")
    @Email(message = "Invalid email format")
    String email,
    
    @Size(min = 8, max = 100, message = "Password must be 8-100 characters")
    String password
) {}
```

## Null Object Pattern

For cases where you need a default behavior:

```java
public interface NotificationSender {
    void send(Notification notification);
}

// Real implementation
public class EmailNotificationSender implements NotificationSender {
    public void send(Notification notification) {
        // send email
    }
}

// Null object - does nothing
public class NoOpNotificationSender implements NotificationSender {
    public static final NoOpNotificationSender INSTANCE = new NoOpNotificationSender();
    
    private NoOpNotificationSender() {}
    
    public void send(Notification notification) {
        // intentionally empty
    }
}

// Usage - no null checks needed
NotificationSender sender = config.notificationsEnabled() 
    ? new EmailNotificationSender()
    : NoOpNotificationSender.INSTANCE;
sender.send(notification);  // Always safe
```
