# Summer Framework — Usage Guide

Detailed usage examples, configuration guides, and best practices for building microservices with Summer Framework.

## Table of Contents

- [Quick Start](#quick-start)
- [Configuration Guide](#configuration-guide)
- [Integration Guidelines](#integration-guidelines)
- [Request Handling](#request-handling)
- [Handler Pattern](#handler-pattern)
- [Exception Handling](#exception-handling)
- [WebClient Integration](#webclient-integration)
- [Testing Framework](#testing-framework)
- [Mock Stubs & Services](#mock-stubs--services)
- [Blackbox Testing](#blackbox-testing)
- [PostgreSQL TestContainers](#postgresql-testcontainers)
- [Jackson Configuration](#jackson-configuration)
- [Advanced Configuration](#advanced-configuration)
- [Best Practices](#best-practices)

---

## Quick Start

### 1. Create Your Application

```java
@SpringBootApplication
@EnableConfigurationProperties
public class UserServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(UserServiceApplication.class, args);
    }

    // Summer Framework auto-configures:
    // - Reactive WebFlux + Netty
    // - Global exception handling
    // - Distributed tracing via Micrometer + OpenTelemetry
    // - Handler pattern with automatic routing
    // - WebClient with connection pooling
    // - Enhanced actuator endpoints
}
```

### 2. Basic Configuration

Create `application.yml`:

```yaml
spring:
  application:
    name: user-service
  webflux:
    multipart:
      max-in-memory-size: 1MB

f8a:
  common:
    enabled: true
    logging:
      enabled: true
      aop:
        enabled: true

server:
  port: 8080

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
```

### 3. Your First Reactive Controller

```java
@RestController
@RequestMapping("/api/users")
public class UserController extends BaseController {

    private final UserService userService;

    @GetMapping("/{id}")
    public Mono<ResponseEntity<User>> getUser(@PathVariable String id) {
        return userService.findById(id)
            .flatMap(responseFactory::success)
            .switchIfEmpty(Mono.error(new CustomException.NotFound("User not found")));
    }

    @PostMapping
    public Mono<ResponseEntity<User>> createUser(@Valid @RequestBody CreateUserRequest request) {
        return execute(request);
    }
}
```

## Configuration Guide

### Environment Variables

```bash
# Core Configuration
export F8A_COMMON_ENABLED=true
export SERVICE_NAME=user-service

# Global Jackson JSON Configuration
export F8A_JACKSON_ENABLED=true
export F8A_JACKSON_FAIL_ON_UNKNOWN_PROPERTIES=false
export F8A_JACKSON_WRITE_DATES_AS_TIMESTAMPS=false
export F8A_JACKSON_INCLUDE_NULL_VALUES=false
export F8A_JACKSON_PROPERTY_NAMING_STRATEGY=LOWER_CAMEL_CASE
export F8A_JACKSON_TIME_ZONE=UTC

# Reactive Logging
export F8A_LOGGING_ENABLED=true
export F8A_LOGGING_AOP_ENABLED=true

# Reactive WebClient
export F8A_WEBCLIENT_MAX_CONNECTIONS=500
export F8A_WEBCLIENT_CONNECT_TIMEOUT=5000
```

### Complete Application Configuration

```yaml
f8a:
  common:
    enabled: ${F8A_COMMON_ENABLED:true}

    # Global Jackson JSON Configuration
    jackson:
      enabled: ${F8A_JACKSON_ENABLED:true}
      fail-on-unknown-properties: ${F8A_JACKSON_FAIL_ON_UNKNOWN_PROPERTIES:false}
      write-dates-as-timestamps: ${F8A_JACKSON_WRITE_DATES_AS_TIMESTAMPS:false}
      include-null-values: ${F8A_JACKSON_INCLUDE_NULL_VALUES:false}
      write-enums-using-to-string: ${F8A_JACKSON_WRITE_ENUMS_USING_TO_STRING:true}
      read-enums-using-to-string: ${F8A_JACKSON_READ_ENUMS_USING_TO_STRING:true}
      property-naming-strategy: ${F8A_JACKSON_PROPERTY_NAMING_STRATEGY:LOWER_CAMEL_CASE}
      date-format: ${F8A_JACKSON_DATE_FORMAT:yyyy-MM-dd'T'HH:mm:ss.SSSXXX}
      time-zone: ${F8A_JACKSON_TIME_ZONE:UTC}

    logging:
      enabled: ${F8A_LOGGING_ENABLED:true}
      aop:
        enabled: ${F8A_LOGGING_AOP_ENABLED:true}
        controller-pattern: ${F8A_LOGGING_AOP_PATTERN:io.f8a.*.controller.*}
        log-headers: ${F8A_LOG_HEADERS:false}
        log-request-body: ${F8A_LOG_REQUEST_BODY:false}
        log-response-body: ${F8A_LOG_RESPONSE_BODY:false}

    exception-handling:
      enabled: ${F8A_EXCEPTION_HANDLING_ENABLED:true}

    webclient:
      enabled: ${F8A_WEBCLIENT_ENABLED:true}
      max-connections: ${F8A_WEBCLIENT_MAX_CONNECTIONS:200}
      connect-timeout-millis: ${F8A_WEBCLIENT_CONNECT_TIMEOUT:10000}
      read-timeout-millis: ${F8A_WEBCLIENT_READ_TIMEOUT:30000}

    actuator:
      enabled: ${F8A_ACTUATOR_ENABLED:true}

spring:
  webflux:
    multipart:
      max-in-memory-size: 1MB
  reactor:
    netty:
      connection-timeout: 30s
      leak-detection: simple
```

## Integration Guidelines

### Project Structure

Follow this recommended structure for your microservice:

```
your-service/
├── src/main/java/io/f8a/yourservice/
│   ├── YourServiceApplication.java     # Main application
│   ├── config/                         # Configuration classes
│   ├── controller/                     # Reactive controllers
│   ├── service/                        # Business logic services
│   ├── repository/                     # Data access layer
│   ├── domain/                         # Domain models
│   ├── dto/                           # Data transfer objects (requests/responses)
│   ├── handler/                       # Request handlers
│   └── exception/                     # Custom exceptions
├── src/main/resources/
│   ├── application.yml                # Main configuration
│   ├── application-prod.yml           # Production config
│   └── db/migration/                  # Flyway migrations
└── src/test/
    ├── java/                          # Unit tests
    └── resources/
        ├── blackbox/                  # Blackbox tests
        │   ├── blackbox_config.json
        │   ├── stubs/                 # WireMock stubs
        │   └── test-cases/            # Test definitions
        └── db/migration/              # Test migrations
```

### Dependencies Setup

For a complete microservice, add these dependencies:

```gradle
dependencies {
    // Summer Framework — use BOM for version management
    implementation platform('io.f8a.summer:summer-platform:<version>')
    implementation 'io.f8a.summer:summer-rest-autoconfigure'
    implementation 'io.f8a.summer:summer-data-autoconfigure'       // if using R2DBC
    implementation 'io.f8a.summer:summer-security-autoconfigure'   // if using APISIX security
    testImplementation 'io.f8a.summer:summer-test'

    // WebFlux (reactive web)
    implementation 'org.springframework.boot:spring-boot-starter-webflux'

    // Database (choose one)
    implementation 'org.springframework.boot:spring-boot-starter-data-r2dbc'
    implementation 'org.postgresql:r2dbc-postgresql'

    // Or for blocking repository
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.postgresql:postgresql'

    // Validation
    implementation 'org.springframework.boot:spring-boot-starter-validation'

    // Database migrations
    implementation 'org.flywaydb:flyway-core'
    implementation 'org.flywaydb:flyway-database-postgresql'
}
```

## Request Handling

### Reactive Controller Patterns

#### Basic CRUD Controller

```java
@RestController
@RequestMapping("/api/users")
@Validated
public class UserController extends BaseController {

    private final UserService userService;

    // GET single resource
    @GetMapping("/{id}")
    public Mono<ResponseEntity<User>> getUser(@PathVariable String id) {
        return userService.findById(id)
            .flatMap(responseFactory::success)
            .onErrorResume(CustomException.NotFound.class,
                ex -> Mono.error(ex));
    }

    // GET collection with filtering
    @GetMapping
    public Mono<ResponseEntity<List<User>>> getUsers(
            @RequestParam(defaultValue = "ACTIVE") UserStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return userService.findByStatus(status, page, size)
            .collectList()
            .flatMap(responseFactory::success);
    }

    // POST create resource using handler pattern
    @PostMapping
    public Mono<ResponseEntity<User>> createUser(@Valid @RequestBody CreateUserRequest request) {
        return execute(request); // Automatically routes to CreateUserRequestHandler
    }

    // PUT update resource
    @PutMapping("/{id}")
    public Mono<ResponseEntity<User>> updateUser(
            @PathVariable String id,
            @Valid @RequestBody UpdateUserRequest request) {
        return userService.update(id, request)
            .flatMap(responseFactory::success)
            .onErrorResume(CustomException.NotFound.class,
                ex -> Mono.error(ex));
    }

    // DELETE resource
    @DeleteMapping("/{id}")
    public Mono<ResponseEntity<Void>> deleteUser(@PathVariable String id) {
        return userService.delete(id)
            .then(Mono.just(ResponseEntity.noContent().build()))
            .onErrorResume(CustomException.NotFound.class,
                ex -> Mono.error(ex));
    }
}
```

#### Handler Pattern Implementation

```java
// Request DTO
@Data
@AllArgsConstructor
public class CreateUserRequest {
    @NotBlank
    private String name;

  @Email
    private String email;
}

// Request Handler
@Component
public class CreateUserRequestHandler extends RequestHandler<CreateUserRequest, User> {

    private final UserRepository userRepository;

    @Override
    public Mono<User> handle(CreateUserRequest request) {
        return userRepository.existsByEmail(request.getEmail())
            .flatMap(exists -> {
                if (exists) {
                    return Mono.error(new CustomException.ValidationException("Email already exists"));
                }
                return userRepository.save(User.builder()
                    .id(UUID.randomUUID().toString())
                    .name(request.getName())
                    .email(request.getEmail())
                    .status(UserStatus.ACTIVE)
                    .createdAt(LocalDateTime.now())
                    .build());
            });
    }
}

// Handler-based Controller
@RestController
@RequestMapping("/api/users")
public class UserController extends BaseController {

    @PostMapping
    public Mono<ResponseEntity<User>> createUser(@Valid @RequestBody CreateUserRequest request) {
        return execute(request); // Automatically routes to CreateUserRequestHandler
    }
}
```

### External Service Integration

```java
@Service
public class ExternalApiService {

    private final WebClient webClient;

    public ExternalApiService(WebClientBuilderFactory factory) {
        this.webClient = factory.createWithBaseUrl("https://api.external.com");
    }

    public Mono<UserDto> getUser(String id) {
        return webClient.get()
            .uri("/users/{id}", id)
            .header(HeaderConstants.CONTENT_TYPE, HeaderConstants.APPLICATION_JSON)
            .retrieve()
            .bodyToMono(UserDto.class)
            .timeout(Duration.ofSeconds(10))
            .retryWhen(Retry.backoff(3, Duration.ofSeconds(1)))
          .onErrorMap(WebClientException.class, ex ->
                new CustomException.ExternalServiceException("Failed to fetch user", ex));
    }

    public Mono<UserDto> createUser(UserDto user) {
        return webClient.post()
            .uri("/users")
            .header(HeaderConstants.CONTENT_TYPE, HeaderConstants.APPLICATION_JSON)
            .bodyValue(user)
            .retrieve()
            .bodyToMono(UserDto.class)
            .doOnNext(createdUser -> log.info("User created: {}", createdUser.getId()));
    }
}
```

## Handler Pattern

The Summer Framework provides a handler-based pattern for processing requests. This allows you to separate business
logic from controllers and provides automatic routing based on request types.

### Core Handler Components

#### Handler Interface

```java
public interface Handler<T, I> {
    Mono<I> handle(T request);
}
```

#### RequestHandler Base Class

```java
public abstract class RequestHandler<T, I> implements Handler<T, I> {
    // Base implementation for request handlers
}
```

#### BaseController

```java
public class BaseController {

  @Autowired
    protected SpringBus springBus;

    /** Execute a request and return a reactive response */
    protected <T, I> Mono<ResponseEntity<I>> execute(T request) {
        return responseFactory.success(this.springBus.execute(request));
    }
}
```

### Creating Request Handlers

#### 1. Define Your Request DTO

```java
@Data
@AllArgsConstructor
@NoArgsConstructor
public class CreateUserRequest {
    @NotBlank
    private String name;

  @Email
    private String email;

    private final UserRole role = UserRole.USER;
}
```

#### 2. Create Request Handler

```java
@Component
public class CreateUserRequestHandler extends RequestHandler<CreateUserRequest, User> {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public CreateUserRequestHandler(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public Mono<User> handle(CreateUserRequest request) {
        return validateRequest(request)
            .flatMap(this::checkEmailUniqueness)
            .map(this::createUser)
            .flatMap(userRepository::save)
            .doOnSuccess(user -> log.info("User created successfully: {}", user.getId()));
    }

    private Mono<CreateUserRequest> validateRequest(CreateUserRequest request) {
        // Additional business validation
        if (request.getRole() == UserRole.ADMIN) {
            return Mono.error(new CustomException.ValidationException("Cannot create admin users"));
        }
        return Mono.just(request);
    }

    private Mono<CreateUserRequest> checkEmailUniqueness(CreateUserRequest request) {
        return userRepository.existsByEmail(request.getEmail())
            .flatMap(exists -> {
                if (exists) {
                    return Mono.error(new CustomException.ValidationException("Email already exists"));
                }
                return Mono.just(request);
            });
    }

    private User createUser(CreateUserRequest request) {
        return User.builder()
            .id(UUID.randomUUID().toString())
            .name(request.getName())
            .email(request.getEmail())
            .role(request.getRole())
            .status(UserStatus.ACTIVE)
            .createdAt(LocalDateTime.now())
            .build();
    }
}
```

#### 3. Use in Controller

```java
@RestController
@RequestMapping("/api/users")
public class UserController extends BaseController {

    @PostMapping
    public Mono<ResponseEntity<User>> createUser(@Valid @RequestBody CreateUserRequest request) {
        return execute(request); // Automatically routes to CreateUserRequestHandler
    }
}
```

### Handler Registry

The framework automatically discovers and registers all `RequestHandler` implementations:

```java
@Component
public class Registry {
    private static final Map<Class<?>, RequestHandler> COMMAND_HANDLER_MAP = new HashMap<>();

  // Automatically scans for RequestHandler beans and registers them by request type
    private void initCommandHandlerBeans() {
        String[] handlerBeanNames = applicationContext.getBeanNamesForType(RequestHandler.class);

      for (String beanName : handlerBeanNames) {
            initCommandHandlerBean(beanName);
        }
    }
}
```

### Advanced Handler Examples

#### Query Handler with Pagination

```java
@Data
@AllArgsConstructor
public class GetUsersRequest {
    private final UserStatus status = UserStatus.ACTIVE;
    private final int page = 0;
    private final int size = 20;
    private final String sortBy = "name";
    private final String sortDirection = "ASC";
}

@Component
public class GetUsersRequestHandler extends RequestHandler<GetUsersRequest, ListWrappedResponse<User>> {

    private final UserRepository userRepository;

    @Override
    public Mono<ListWrappedResponse<User>> handle(GetUsersRequest request) {
        return userRepository.findByStatusWithPagination(
                request.getStatus(),
            PageRequest.of(request.getPage(), request.getSize(),
                    Sort.by(Sort.Direction.fromString(request.getSortDirection()), request.getSortBy()))
            )
            .collectList()
            .zipWith(userRepository.countByStatus(request.getStatus()))
            .map(tuple -> ListWrappedResponse.<User>builder()
                .content(tuple.getT1())
                .totalElements(tuple.getT2())
                .totalPages((int) Math.ceil((double) tuple.getT2() / request.getSize()))
                .page(request.getPage())
                .size(request.getSize())
                .build());
    }
}
```

#### Update Handler with Optimistic Locking

```java
@Data
public class UpdateUserRequest {
    @NotBlank
    private String name;

  @Email
    private String email;

  private UserRole role;

  private Long version; // For optimistic locking
}

@Component
public class UpdateUserRequestHandler extends RequestHandler<UpdateUserRequest, User> {

    private final UserRepository userRepository;

    @Override
    public Mono<User> handle(UpdateUserRequest request) {
        return userRepository.findById(request.getId())
            .switchIfEmpty(Mono.error(new CustomException.NotFound("User not found")))
            .flatMap(existingUser -> validateVersion(existingUser, request.getVersion()))
            .flatMap(existingUser -> updateUser(existingUser, request))
            .flatMap(userRepository::save);
    }

    private Mono<User> validateVersion(User existingUser, Long requestVersion) {
        if (!existingUser.getVersion().equals(requestVersion)) {
            return Mono.error(new CustomException.Conflict("User has been modified by another process"));
        }
        return Mono.just(existingUser);
    }

    private Mono<User> updateUser(User existingUser, UpdateUserRequest request) {
        existingUser.setName(request.getName());
        existingUser.setEmail(request.getEmail());
        existingUser.setRole(request.getRole());
        existingUser.setUpdatedAt(LocalDateTime.now());
        return Mono.just(existingUser);
    }
}
```

### Handler Pattern Benefits

1. **Separation of Concerns**: Business logic is separated from controllers
2. **Automatic Routing**: Framework automatically routes requests to appropriate handlers
3. **Testability**: Handlers can be easily unit tested in isolation
4. **Reusability**: Handlers can be reused across different controllers
5. **Type Safety**: Strong typing between request and response types
6. **Clean Architecture**: Promotes clean, maintainable code structure

### Handler Best Practices

1. **Single Responsibility**: Each handler should handle one specific request type
2. **Reactive**: Always return `Mono<T>` or `Flux<T>` for reactive processing
3. **Error Handling**: Use proper exception handling with custom exceptions
4. **Validation**: Implement both annotation-based and business rule validation
5. **Logging**: Add appropriate logging for monitoring and debugging
6. **Testing**: Write comprehensive unit tests for each handler

## Exception Handling

### Using ViewableException and CommonExceptions

Use `ViewableException` for HTTP errors with structured error details. `CommonExceptions` provides predefined error
codes mapped to HTTP statuses.

```java
// Simple — code + status
throw new ViewableException("user.not.found", HttpStatus.NOT_FOUND);

// Using CommonExceptions enum
throw CommonExceptions.RESOURCE_NOT_FOUND.toException();

// With field-level details (fluent builder — chainable)
throw CommonExceptions.VALIDATION_ERROR.toException()
    .detail("email", "Invalid email format", request.getEmail())
    .detail("age", "Must be at least 18", String.valueOf(request.getAge()));

// Issue only (no value)
throw CommonExceptions.INVALID_REQUEST.toException()
    .detailIssue("password", "Must contain at least one uppercase letter");

// Value only (no issue)
throw CommonExceptions.CONFLICT.toException()
    .detailValue("username", request.getUsername());
```

### Custom Business Exception Enum

Follow the `CommonExceptions` pattern for domain-specific errors:

```java
@Getter
@RequiredArgsConstructor
public enum UserExceptions implements IntoViewableException {
  USER_NOT_FOUND("user.not.found", HttpStatus.NOT_FOUND),
  EMAIL_ALREADY_EXISTS("user.email.already.exists", HttpStatus.CONFLICT),
  ACCOUNT_DISABLED("user.account.disabled", HttpStatus.FORBIDDEN);

  public static final String PREFIX = "usr";
  private final String code;
  private final HttpStatus httpStatus;

  @Override
  public ViewableException toException() {
    return new ViewableException(String.format("%s.%s", PREFIX, this.code), this.httpStatus);
  }
}

// Usage with details
throw UserExceptions.EMAIL_ALREADY_EXISTS.toException()
    .detailValue("email", request.getEmail());
```

### Service Layer Error Handling

```java
@Service
@Slf4j
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final ExternalApiService externalApiService;

    public Mono<User> processUser(String userId) {
        return findUser(userId)
            .flatMap(this::enrichWithExternalData)
            .doOnSuccess(user -> log.info("User processed successfully: {}", user.getId()))
            .doOnError(ex -> log.error("Failed to process user: {}", userId, ex));
    }

    private Mono<User> findUser(String id) {
        return userRepository.findById(id)
            .switchIfEmpty(Mono.error(
                CommonExceptions.RESOURCE_NOT_FOUND.toException()
                    .detailValue("userId", id)));
    }

    private Mono<User> enrichWithExternalData(User user) {
        return externalApiService.getUserDetails(user.getId())
            .map(details -> user.toBuilder().externalData(details).build())
            .onErrorResume(ex -> {
                log.warn("Failed to enrich user data, continuing without enrichment", ex);
                return Mono.just(user); // Graceful degradation
            });
    }
}
```

### Global Error Response Format

The framework automatically handles exceptions and returns standardized error responses:

```json
{
  "code": "com.resource.not.found",
  "message": "com.resource.not.found",
  "traceId": "abc123def456",
  "timestamp": "2026-03-04T10:30:00Z",
  "details": [
    { "field": "userId", "value": "user-123" }
  ]
}
```

## WebClient Integration

```java
@Service
public class ExternalApiService {

    private final WebClient webClient;

    public ExternalApiService(WebClientBuilderFactory factory) {
        this.webClient = factory.createWithBaseUrl("https://api.external.com");
    }

    public Mono<UserDto> getUser(String id) {
        return webClient.get()
            .uri("/users/{id}", id)
            .header(HeaderConstants.CONTENT_TYPE, HeaderConstants.APPLICATION_JSON)
            .retrieve()
            .bodyToMono(UserDto.class)
            .timeout(Duration.ofSeconds(10))
            .retryWhen(Retry.backoff(3, Duration.ofSeconds(1)))
            .onErrorMap(WebClientException.class, ex ->
                new CustomException.ExternalServiceException("Failed to fetch user", ex));
    }
}
```

## Testing Framework

### Unit Testing with WebTestClient

```java
@WebFluxTest(UserController.class)
class UserControllerTest {

    @Autowired
    private WebTestClient webTestClient;

    @MockBean
    private UserService userService;

    @Test
    void shouldGetUserSuccessfully() {
        // Given
        String userId = "user-123";
        User mockUser = User.builder()
            .id(userId)
            .name("John Doe")
            .email("john@example.com")
            .build();

        when(userService.findById(userId)).thenReturn(Mono.just(mockUser));

        // When & Then
        webTestClient.get()
            .uri("/api/users/{id}", userId)
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.id").isEqualTo(userId)
            .jsonPath("$.name").isEqualTo("John Doe");
    }

    @Test
    void shouldReturnNotFoundForNonExistentUser() {
        // Given
        String userId = "non-existent";
        when(userService.findById(userId))
            .thenReturn(Mono.error(new CustomException.NotFound("User not found")));

        // When & Then
        webTestClient.get()
            .uri("/api/users/{id}", userId)
            .exchange()
            .expectStatus().isNotFound()
            .expectBody()
            .jsonPath("$.success").isEqualTo(false)
            .jsonPath("$.message").isEqualTo("User not found");
    }
}
```

### Integration Testing

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = {
    "spring.r2dbc.url=r2dbc:h2:mem:///testdb",
    "f8a.common.logging.aop.enabled=false"
})
class UserServiceIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Autowired
    private UserRepository userRepository;

    @BeforeEach
    void setUp() {
        userRepository.deleteAll().block();
    }

    @Test
    void shouldCreateAndRetrieveUser() {
        // Given
        CreateUserRequest request = CreateUserRequest.builder()
            .name("Jane Doe")
            .email("jane@example.com")
            .build();

        // When - Create user
        webTestClient.post()
            .uri("/api/users")
            .bodyValue(request)
            .exchange()
            .expectStatus().isCreated()
            .expectBody()
            .jsonPath("$.name").isEqualTo("Jane Doe");

        // Then - Verify in database
        StepVerifier.create(userRepository.findByEmail("jane@example.com"))
            .expectNextMatches(user -> user.getName().equals("Jane Doe"))
            .verifyComplete();
    }
}
```

## Mock Stubs & Services

### Project Structure for Testing

```
src/test/resources/blackbox/
├── blackbox_config.json          # Main test configuration
├── stubs_config.json             # Stub-only configuration
├── stubs/                        # WireMock stub definitions
│   ├── user-service/
│   │   ├── mappings/             # Request mappings
│   │   │   ├── get-user-success.json
│   │   │   └── get-user-error.json
│   │   └── __files/             # Response templates
│   │       ├── user-success-response.json
│   │       └── user-error-response.json
│   ├── payment-service/
│   │   ├── mappings/
│   │   │   └── create-payment.json
│   │   └── __files/
│   │       └── payment-response.json
│   └── notification-service/
└── test-cases/                   # Test case definitions
    └── user-service/
        ├── crud-operations.json
        ├── validation-tests.json
        └── error-scenarios.json
```

### Configuration Files

#### Main Configuration (`blackbox_config.json`)

```json
{
  "application": {
    "name": "user-service",
    "base_url": "http://localhost:8080",
    "health_endpoint": "/actuator/health",
    "startup_timeout_seconds": 60
  },
  "stubs": {
    "services": [
      {
        "name": "external-user-service",
        "port": 8091,
        "stubs_data_path": "src/test/resources/blackbox/stubs/user-service",
        "enabled": true,
        "startup_delay_ms": 1000
      },
      {
        "name": "payment-service",
        "port": 8092,
        "stubs_data_path": "src/test/resources/blackbox/stubs/payment-service",
        "enabled": true
      }
    ]
  },
  "test_cases": {
    "root_path": "src/test/resources/blackbox/test-cases",
    "file_patterns": [".*\\.json$"],
    "timeout_seconds": 30,
    "recursive_scan": true,
    "parallel_execution": false,
    "retry_attempts": 2
  }
}
```

#### Stub-Only Configuration (`stubs_config.json`)

```json
{
  "services": [
    {
      "name": "external-user-service",
      "port": 8091,
      "stubs_data_path": "src/test/resources/blackbox/stubs/user-service",
      "enabled": true
    },
    {
      "name": "payment-service",
      "port": 8092,
      "stubs_data_path": "src/test/resources/blackbox/stubs/payment-service",
      "enabled": true
    }
  ]
}
```

### Creating WireMock Stubs

#### Request Mapping (`stubs/user-service/mappings/get-user-success.json`)

```json
{
  "request": {
    "method": "GET",
    "urlPattern": "/users/([a-zA-Z0-9]+)",
    "headers": {
      "Content-Type": {
        "equalTo": "application/json"
      }
    }
  },
  "response": {
    "status": 200,
    "headers": {
      "Content-Type": "application/json"
    },
    "bodyFileName": "user-success-response.json",
    "transformers": ["response-template"],
    "delayDistribution": {
      "type": "lognormal",
      "median": 50,
      "sigma": 0.1
    }
  }
}
```

#### Response Template (`stubs/user-service/__files/user-success-response.json`)

```json
{
  "id": "{{request.pathSegments.[1]}}",
  "username": "testuser_{{request.pathSegments.[1]}}",
  "email": "{{request.pathSegments.[1]}}@example.com",
  "firstName": "Test",
  "lastName": "User",
  "status": "ACTIVE",
  "createdAt": "{{now format='yyyy-MM-dd HH:mm:ss'}}",
  "updatedAt": "{{now format='yyyy-MM-dd HH:mm:ss'}}",
  "metadata": {
    "source": "wiremock",
    "requestId": "{{randomValue length=12 type='ALPHANUMERIC'}}"
  }
}
```

#### Error Scenario (`stubs/user-service/mappings/get-user-error.json`)

```json
{
  "request": {
    "method": "GET",
    "urlPattern": "/users/error.*",
    "headers": {
      "Content-Type": {
        "equalTo": "application/json"
      }
    }
  },
  "response": {
    "status": 404,
    "headers": {
      "Content-Type": "application/json"
    },
    "body": "{\"error\":\"User not found\",\"code\":\"USER_NOT_FOUND\",\"timestamp\":\"{{now format='yyyy-MM-dd HH:mm:ss'}}\"}"
  }
}
```

### Running Stubs Standalone

Create a standalone stub runner for development:

```java
package your.package.stubs;

import io.f8a.summer.test.wiremock.WireMockServiceManager;
import io.f8a.summer.test.utils.StubConfigurationUtils;

public class StandaloneStubsRunner {

  public static void main(String[] args) throws Exception {
        String configPath = "src/test/resources/blackbox/stubs_config.json";

    WireMockServiceManager serviceManager = new WireMockServiceManager();

    try {
            // Load and start stub services
            var config = StubConfigurationUtils.loadStubsConfiguration(configPath);
            StubConfigurationUtils.startAllStubServices(serviceManager, config);

      System.out.println("Stub services started successfully!");
            System.out.println("Services running:");

      config.forEach(service -> {
                if (service.isEnabled()) {
                    System.out.println("   - " + service.getName() + " on port " + service.getPort());
                }
            });

      System.out.println("Press Enter to stop services...");
            System.in.read();

    } finally {
            serviceManager.stopAllServers();
            System.out.println("All services stopped.");
        }
    }
}
```

Add to your `build.gradle`:

```gradle
task runStubs(type: JavaExec) {
    classpath = sourceSets.test.runtimeClasspath
    mainClass = 'your.package.stubs.StandaloneStubsRunner'
    description = 'Run WireMock stubs for development'
}
```

Run with: `./gradlew runStubs`

## Blackbox Testing

### Test Case Structure

#### CRUD Operations Test (`test-cases/user-service/crud-operations.json`)

```json
{
  "test_suite": "User CRUD Operations",
  "setup": {
    "stubs": [
      {
        "service": "external-user-service",
        "stub_file": "get-user-success.json"
      }
    ]
  },
  "tests": [
    {
      "name": "Create User Success",
      "description": "Should create a new user successfully",
      "test": {
        "method": "POST",
        "url": "http://localhost:8080/api/users",
        "headers": {
          "Content-Type": "application/json",
          "X-Request-ID": "test-create-user-001"
        },
        "body": {
          "name": "John Doe",
          "email": "john.doe@example.com"
        }
      },
      "assertions": {
        "status_code": 201,
        "headers": {
          "Content-Type": "application/json"
        },
        "json": {
          "$.success": true,
          "$.data.id": {"type": "string", "pattern": "^[a-f0-9-]{36}$"},
          "$.data.name": "John Doe",
          "$.data.email": "john.doe@example.com",
          "$.data.status": "ACTIVE"
        },
        "response_time_ms": 1000
      },
      "post_actions": [
        {
          "type": "store_variable",
          "name": "created_user_id",
          "json_path": "$.data.id"
        }
      ]
    },
    {
      "name": "Get User Success",
      "description": "Should retrieve user by ID",
      "test": {
        "method": "GET",
        "url": "http://localhost:8080/api/users/${created_user_id}",
        "headers": {
          "Accept": "application/json"
        }
      },
      "assertions": {
        "status_code": 200,
        "json": {
          "$.success": true,
          "$.data.id": "${created_user_id}",
          "$.data.name": "John Doe"
        }
      }
    }
  ]
}
```

#### Validation Tests (`test-cases/user-service/validation-tests.json`)

```json
{
  "test_suite": "Input Validation Tests",
  "tests": [
    {
      "name": "Create User - Missing Name",
      "test": {
        "method": "POST",
        "url": "http://localhost:8080/api/users",
        "headers": {"Content-Type": "application/json"},
        "body": {
          "email": "test@example.com"
        }
      },
      "assertions": {
        "status_code": 400,
        "json": {
          "$.success": false,
          "$.message": {"type": "string", "contains": "Name is required"}
        }
      }
    },
    {
      "name": "Create User - Invalid Email",
      "test": {
        "method": "POST",
        "url": "http://localhost:8080/api/users",
        "headers": {"Content-Type": "application/json"},
        "body": {
          "name": "John Doe",
          "email": "invalid-email"
        }
      },
      "assertions": {
        "status_code": 400,
        "json": {
          "$.success": false,
          "$.message": {"type": "string", "contains": "Invalid email format"}
        }
      }
    }
  ]
}
```

### Blackbox Test Implementation

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestMethodOrder(OrderAnnotation.class)
public class UserServiceBlackboxTest {

    private static WireMockServiceManager serviceManager;
    private static BlackboxTestConfig config;

    @BeforeAll
    static void setUpAll() throws Exception {
        // Load blackbox configuration
        config = BlackboxTestUtils.loadConfiguration("src/test/resources/blackbox/blackbox_config.json");

        // Initialize WireMock service manager
        serviceManager = new WireMockServiceManager();

        // Start all stub services
        config.getStubs().getServices().forEach(service -> {
            if (service.isEnabled()) {
                serviceManager.startService(service.getName(), service.getPort(), service.getStubsDataPath());
            }
        });

        // Wait for services to be ready
        BlackboxTestUtils.waitForServicesReady(config);
    }

    @AfterAll
    static void tearDownAll() {
        if (serviceManager != null) {
            serviceManager.stopAllServices();
        }
    }

    @TestFactory
    @DisplayName("User Service CRUD Operations")
    Stream<DynamicTest> userCrudOperations() {
        return TestCaseUtils.loadTestCases("src/test/resources/blackbox/test-cases/user-service/crud-operations.json")
            .stream()
            .map(testCase -> DynamicTest.dynamicTest(
                testCase.getName(),
                () -> executeTestCase(testCase)
            ));
    }

    @TestFactory
    @DisplayName("Input Validation Tests")
    Stream<DynamicTest> inputValidationTests() {
        return TestCaseUtils.loadTestCases("src/test/resources/blackbox/test-cases/user-service/validation-tests.json")
            .stream()
            .map(testCase -> DynamicTest.dynamicTest(
                testCase.getName(),
                () -> executeTestCase(testCase)
            ));
    }

    private void executeTestCase(TestCaseInfo testCase) throws Exception {
        // Setup test environment
        BlackboxTestUtils.setupTestCase(testCase, serviceManager, config);

        try {
            // Execute the test
            TestExecutionResult result = TestExecutionUtils.executeReactiveTest(testCase, config);

            // Assert results
            TestAssertionUtils.assertTestResult(result, testCase.getAssertions());

            // Store variables for subsequent tests
            TestVariableUtils.storeTestVariables(testCase, result);

        } finally {
            // Cleanup test environment
            BlackboxTestUtils.cleanupTestCase(testCase, config);
        }
    }
}
```

### Running Blackbox Tests

Add to your `build.gradle`:

```gradle
test {
    useJUnitPlatform()

    // Separate blackbox tests
    systemProperty 'junit.jupiter.execution.parallel.enabled', 'false'
    systemProperty 'spring.profiles.active', 'blackbox-test'
}

task blackboxTest(type: Test) {
    useJUnitPlatform()
    include '**/blackbox/**'
    systemProperty 'spring.profiles.active', 'blackbox-test'

    reports {
        html.destination = file("$buildDir/reports/blackbox-tests")
        junitXml.destination = file("$buildDir/test-results/blackbox-tests")
    }
}
```

Run with:

```bash
# Run all tests
./gradlew test

# Run only blackbox tests
./gradlew blackboxTest

# Run specific test suite
./gradlew blackboxTest --tests "UserServiceBlackboxTest.userCrudOperations"
```

## PostgreSQL TestContainers

### Basic Setup

```java
@Testcontainers
class UserServiceIntegrationTest {

  @Container
    static PostgresTestContainer postgres = PostgresTestContainer.create()
        .withDatabaseName("testdb")
        .withUsername("testuser")
        .withPassword("testpass");

  @BeforeAll
    static void setup() {
        // Run Flyway migrations automatically
        postgres.runFlywayMigrations("classpath:db/migration");
    }

  @Test
    void shouldTestWithRealDatabase() {
        // Get connection details
        String jdbcUrl = postgres.getJdbcUrl();
        String r2dbcUrl = postgres.getR2dbcUrl();

    // Test database operations
    DatabaseTestUtils.executeUpdate(postgres,
            "INSERT INTO users (name, email) VALUES ('Test User', 'test@example.com')");

    // Verify results
        assertEquals(1, DatabaseTestUtils.getTableRowCount(postgres, "users"));
    }
}
```

### Advanced Database Testing

```java
@SpringBootTest
@Testcontainers
class DatabaseIntegrationTest {

    @Container
    static PostgresTestContainer postgres = PostgresTestContainer.create();

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", postgres::getR2dbcUrl);
        registry.add("spring.r2dbc.username", postgres::getUsername);
        registry.add("spring.r2dbc.password", postgres::getPassword);
        registry.add("spring.flyway.url", postgres::getJdbcUrl);
        registry.add("spring.flyway.user", postgres::getUsername);
        registry.add("spring.flyway.password", postgres::getPassword);
    }

    @BeforeAll
    static void initDatabase() {
        // Run migrations
        postgres.runFlywayMigrations("classpath:db/migration");

      // Load test data
        postgres.executeSqlScript("classpath:test-data.sql");
    }

    @Test
    void shouldPersistUserData() {
        // Your integration test here
        // Database is automatically configured and ready to use
    }
}
```

### Database Test Utilities

```java
public class DatabaseTestUtils {

    // Check if table exists
    public static boolean tableExists(PostgresTestContainer container, String tableName) {
        String sql = "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = ?)";
        return queryForBoolean(container, sql, tableName);
    }

    // Get row count
    public static int getTableRowCount(PostgresTestContainer container, String tableName) {
        String sql = "SELECT COUNT(*) FROM " + tableName;
        return queryForInt(container, sql);
    }

    // Execute update query
    public static int executeUpdate(PostgresTestContainer container, String sql, Object... params) {
        try (Connection conn = container.createConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {

          for (int i = 0; i < params.length; i++) {
                stmt.setObject(i + 1, params[i]);
            }

          return stmt.executeUpdate();
        } catch (SQLException e) {
            throw new RuntimeException("Failed to execute update", e);
        }
    }

    // Query for single string value
    public static String queryForString(PostgresTestContainer container, String sql, Object... params) {
        try (Connection conn = container.createConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {

          for (int i = 0; i < params.length; i++) {
                stmt.setObject(i + 1, params[i]);
            }

          try (ResultSet rs = stmt.executeQuery()) {
                return rs.next() ? rs.getString(1) : null;
            }
        } catch (SQLException e) {
            throw new RuntimeException("Failed to execute query", e);
        }
    }
}
```

### Database Migration Setup

Create Flyway migrations in `src/main/resources/db/migration/`:

```sql
-- V1__Create_users_table.sql
CREATE TABLE users (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- V2__Create_audit_logs_table.sql
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    entity_id VARCHAR(36) NOT NULL,
    action VARCHAR(50) NOT NULL,
    user_id VARCHAR(36),
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_values JSONB,
    new_values JSONB
);
```

Test migrations in `src/test/resources/db/migration/`:

```sql
-- V999__Insert_test_data.sql
INSERT INTO users (id, name, email, status) VALUES
('test-user-1', 'Test User 1', 'test1@example.com', 'ACTIVE'),
('test-user-2', 'Test User 2', 'test2@example.com', 'INACTIVE');
```

## Jackson Configuration

The Summer Framework provides comprehensive JSON serialization/deserialization configuration that ensures consistency
across all services. The global Jackson configuration is automatically applied to all ObjectMapper instances, including
those used by WebFlux, WebClient, and custom components.

### Default Configuration

```java
@Component
public class MyService {

  @Autowired
    private JsonUtils jsonUtils;        // Utility for JSON operations

  @Autowired
    private ObjectMapper objectMapper;  // Globally configured ObjectMapper

  public void example() {
        MyObject obj = new MyObject();

    // Automatic serialization with global settings
        String json = jsonUtils.toJson(obj);

    // Automatic deserialization with global settings
        Optional<MyObject> parsed = jsonUtils.fromJson(json, MyObject.class);
    }
}
```

### Configuration Properties

All Jackson settings can be customized via configuration:

```yaml
f8a:
  common:
    jackson:
      enabled: true                              # Enable/disable Jackson config
      fail-on-unknown-properties: false          # Ignore unknown JSON properties
      write-dates-as-timestamps: false           # Use ISO-8601 date strings
      include-null-values: false                 # Exclude null values from JSON
      fail-on-empty-beans: false                 # Allow empty objects
      write-enums-using-to-string: true          # Use enum.toString() for serialization
      read-enums-using-to-string: true           # Use enum.toString() for deserialization
      accept-empty-string-as-null-object: true   # Treat empty strings as null
      property-naming-strategy: LOWER_CAMEL_CASE # Property naming convention
      date-format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX" # ISO-8601 with timezone
      time-zone: UTC                             # Default timezone
```

### Advanced Customization

For advanced use cases, you can extend the configuration:

```java
@Configuration
public class CustomJacksonConfig {

  @Bean
    @Primary
    public ObjectMapper customObjectMapper(ObjectMapper defaultMapper) {
        // Start with the global configuration
        ObjectMapper mapper = defaultMapper.copy();

    // Add custom modules or settings
        mapper.registerModule(new CustomModule());
        mapper.configure(JsonGenerator.Feature.WRITE_BIGDECIMAL_AS_PLAIN, true);

    return mapper;
    }
}
```

### JsonUtils Utility

The framework provides a convenient `JsonUtils` component for common JSON operations:

```java
@Service
public class UserService {

  @Autowired
    private JsonUtils jsonUtils;

  public void processUser(String userJson) {
        // Parse JSON with error handling
        Optional<User> user = jsonUtils.fromJson(userJson, User.class);

    if (user.isPresent()) {
            // Convert to different type
            Optional<UserDTO> dto = jsonUtils.convertValue(user.get(), UserDTO.class);

      // Serialize with pretty printing
            String prettyJson = jsonUtils.toPrettyJson(dto.orElse(null));

      // Convert to Map for dynamic access
            Optional<Map<String, Object>> map = jsonUtils.fromJsonToMap(userJson);
        }
    }
}
```

### Supported Jackson Modules

The framework automatically includes:

- **JavaTimeModule**: Java 8+ date/time API support
- **Jdk8Module**: Optional, OptionalInt, OptionalLong support
- **ParameterNamesModule**: Constructor parameter name retention

### Jackson Best Practices

1. **Use JsonUtils**: Prefer `JsonUtils` over direct `ObjectMapper` for consistent error handling
2. **Configure Globally**: Set Jackson properties in configuration rather than per-component
3. **Test JSON Serialization**: Always test your DTOs with the global configuration
4. **Handle Optionals**: Use `Optional<T>` return types for safe JSON parsing
5. **Document Date Formats**: Clearly document expected date formats in your API

## Advanced Configuration

### Production Configuration

```yaml
# application-prod.yml
f8a:
  common:
    logging:
      aop:
        enabled: true
        log-headers: false      # Security in production
        log-request-body: false # Performance in production
        log-response-body: false

    webclient:
      max-connections: 1000     # High throughput
      connect-timeout-millis: 5000
      read-timeout-millis: 15000
      event-loop-threads: 8     # Match CPU cores

    exception-handling:
      enabled: true

spring:
  reactor:
    netty:
      connection-timeout: 10s
      leak-detection: paranoid  # Enhanced monitoring

server:
  netty:
    connection-timeout: 20s
    h2c-max-content-length: 0
    initial-buffer-size: 128
    max-chunk-size: 8192
    max-initial-line-length: 4096
    validate-headers: true

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized
  metrics:
    export:
      prometheus:
        enabled: true
```

### Docker Configuration

```dockerfile
FROM openjdk:17-jdk-slim

ENV F8A_COMMON_ENABLED=true
ENV F8A_WEBCLIENT_MAX_CONNECTIONS=500
ENV F8A_LOGGING_AOP_ENABLED=true
ENV F8A_INCLUDE_STACK_TRACE=false

COPY target/app.jar app.jar

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "/app.jar"]
```

### Monitoring Integration

```java
@Configuration
public class MonitoringConfig {

    @Bean
    public WebFilter metricsWebFilter(MeterRegistry meterRegistry) {
        return new MetricsWebFilter(meterRegistry);
    }

    @Bean
    public TimedAspect timedAspect(MeterRegistry meterRegistry) {
        return new TimedAspect(meterRegistry);
    }

    @Bean
    public MeterRegistryCustomizer<MeterRegistry> metricsCommonTags() {
        return registry -> registry.config()
            .commonTags("application", "user-service")
            .commonTags("environment", getEnvironment());
    }
}
```

## Best Practices

### Microservice Development Checklist

#### Code Quality

- Use reactive streams (Mono/Flux) consistently
- Implement proper error handling with custom exceptions
- Add comprehensive logging with distributed tracing (Micrometer + OpenTelemetry)
- Use handler pattern for request processing
- Validate all inputs with Bean Validation
- Implement circuit breaker pattern for external calls

#### Testing Strategy

- Unit tests for all service methods (80%+ coverage)
- Integration tests for controller endpoints
- Blackbox tests for end-to-end scenarios
- Performance tests for critical paths
- Contract tests for external service interactions

#### Production Readiness

- Health checks and metrics exposure
- Proper configuration externalization
- Security headers and input sanitization
- Request/response logging (production-safe)
- Database connection pooling
- Graceful shutdown handling

#### Monitoring & Observability

- Structured logging with correlation IDs
- Custom metrics for business operations
- Distributed tracing integration
- Error rate and latency monitoring
- Database query performance monitoring

### Common Patterns

#### Error Handling Pattern

```java
@Service
public class UserService {

    public Mono<User> processUser(String userId) {
        return validateUserId(userId)
            .flatMap(this::findUser)
            .flatMap(this::enrichUser)
            .onErrorMap(ValidationException.class, ex ->
                new CustomException.BadRequest("Invalid user data: " + ex.getMessage()))
            .onErrorMap(DataAccessException.class, ex ->
                new CustomException.InternalServerError("Database error"))
            .doOnError(ex -> log.error("Failed to process user: {}", userId, ex));
    }
}
```

#### Reactive Caching Pattern

```java
@Service
public class UserService {

    private final CacheManager cacheManager;

    public Mono<User> findById(String id) {
        return Mono.fromCallable(() -> cacheManager.getCache("users").get(id, User.class))
            .cast(User.class)
            .switchIfEmpty(
                userRepository.findById(id)
                    .doOnNext(user -> cacheManager.getCache("users").put(id, user))
            );
    }
}
```

#### Bulk Operations Pattern

```java
@Service
public class UserService {

    public Flux<User> bulkCreate(List<CreateUserRequest> requests) {
        return Flux.fromIterable(requests)
            .flatMap(this::validateRequest)
            .map(this::mapToUser)
            .buffer(10) // Process in batches of 10
            .flatMap(userRepository::saveAll)
            .doOnNext(user -> log.debug("Created user: {}", user.getId()));
    }
}
```

### Development Setup

```bash
# Clone and setup project
git clone https://github.com/f8a/your-service.git
cd your-service

# Build project
./gradlew build

# Run tests
./gradlew test

# Run blackbox tests
./gradlew blackboxTest

# Run stubs for development
./gradlew runStubs

# Apply formatting
./gradlew spotlessApply
```

### Development Guidelines

- **Reactive First**: All new features must be reactive (Mono/Flux)
- **Non-blocking**: No blocking operations in reactive chains
- **Handler Pattern**: Use request handlers for business logic processing
- **Error Handling**: Proper error propagation and recovery
- **Testing**: Comprehensive reactive testing with WebTestClient
- **Documentation**: Clear reactive examples and patterns
