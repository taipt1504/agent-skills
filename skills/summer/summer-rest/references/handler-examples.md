# Summer REST — Handler Examples

## Full CRUD Controller

```java
@RestController
@RequestMapping("/api/users")
@Validated
public class UserController extends BaseController {

    private final UserService userService;

    @GetMapping("/{id}")
    public Mono<ResponseEntity<User>> getUser(@PathVariable String id) {
        return userService.findById(id)
            .flatMap(responseFactory::success)
            .switchIfEmpty(Mono.error(CommonExceptions.RESOURCE_NOT_FOUND.toException()
                .detailValue("userId", id)));
    }

    @GetMapping
    public Mono<ResponseEntity<List<User>>> getUsers(
            @RequestParam(defaultValue = "ACTIVE") UserStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return userService.findByStatus(status, page, size)
            .collectList()
            .flatMap(responseFactory::success);
    }

    @PostMapping
    public Mono<ResponseEntity<User>> createUser(@Valid @RequestBody CreateUserRequest request) {
        return execute(request); // routes to CreateUserRequestHandler
    }

    @PutMapping("/{id}")
    public Mono<ResponseEntity<User>> updateUser(
            @PathVariable String id,
            @Valid @RequestBody UpdateUserRequest request) {
        return userService.update(id, request)
            .flatMap(responseFactory::success);
    }

    @DeleteMapping("/{id}")
    public Mono<ResponseEntity<Void>> deleteUser(@PathVariable String id) {
        return userService.delete(id)
            .then(Mono.just(ResponseEntity.noContent().build()));
    }
}
```

## Request Handler with Validation

```java
@Data
@AllArgsConstructor
public class CreateUserRequest {
    @NotBlank private String name;
    @Email private String email;
}

@Component
public class CreateUserRequestHandler extends RequestHandler<CreateUserRequest, User> {

    private final UserRepository userRepository;

    @Override
    public Mono<User> handle(CreateUserRequest request) {
        return userRepository.existsByEmail(request.getEmail())
            .flatMap(exists -> {
                if (exists) {
                    return Mono.error(CommonExceptions.CONFLICT.toException()
                        .detailValue("email", request.getEmail()));
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
```

## Query Handler with Pagination

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
                    Sort.by(Sort.Direction.fromString(request.getSortDirection()), request.getSortBy())))
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

## Update Handler with Optimistic Locking

```java
@Data
public class UpdateUserRequest {
    @NotBlank private String name;
    @Email private String email;
    private UserRole role;
    private Long version;
}

@Component
public class UpdateUserRequestHandler extends RequestHandler<UpdateUserRequest, User> {

    private final UserRepository userRepository;

    @Override
    public Mono<User> handle(UpdateUserRequest request) {
        return userRepository.findById(request.getId())
            .switchIfEmpty(Mono.error(CommonExceptions.RESOURCE_NOT_FOUND.toException()))
            .flatMap(existing -> {
                if (!existing.getVersion().equals(request.getVersion())) {
                    return Mono.error(CommonExceptions.CONFLICT.toException()
                        .detailIssue("version", "User has been modified by another process"));
                }
                existing.setName(request.getName());
                existing.setEmail(request.getEmail());
                existing.setRole(request.getRole());
                existing.setUpdatedAt(LocalDateTime.now());
                return userRepository.save(existing);
            });
    }
}
```

## Handler Registry Internals

`Registry` scans all `RequestHandler` beans at startup, maps each handler's request type:

```java
@Component
public class Registry {
    private static final Map<Class<?>, RequestHandler> COMMAND_HANDLER_MAP = new HashMap<>();

    private void initCommandHandlerBeans() {
        String[] handlerBeanNames = applicationContext.getBeanNamesForType(RequestHandler.class);
        for (String beanName : handlerBeanNames) {
            initCommandHandlerBean(beanName);
        }
    }
}
```

`SpringBus.dispatch(request)` looks up handler by request class. `BaseController.execute(request)` calls `SpringBus`.

## External Service Integration with WebClient

```java
@Service
public class ExternalApiService {
    private final WebClient webClient;

    public ExternalApiService(WebClientBuilderFactory factory) {
        this.webClient = factory.newClient(
            WebClientBuilderOptions.builder()
                .baseUrl("https://api.external.com")
                .errorHandling(false).build());
    }

    public Mono<UserDto> getUser(String id) {
        return webClient.get()
            .uri("/users/{id}", id)
            .retrieve()
            .bodyToMono(UserDto.class)
            .timeout(Duration.ofSeconds(10))
            .retryWhen(Retry.backoff(3, Duration.ofSeconds(1)))
            .onErrorMap(WebClientException.class, ex ->
                CommonExceptions.SERVICE_UNAVAILABLE.toException());
    }
}
```

## Custom Exception Enum Pattern

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

// Usage with field-level details
throw UserExceptions.EMAIL_ALREADY_EXISTS.toException()
    .detailValue("email", request.getEmail());

// With issue
throw CommonExceptions.VALIDATION_ERROR.toException()
    .detail("email", "Invalid email format", request.getEmail())
    .detail("age", "Must be at least 18", String.valueOf(request.getAge()));

// Issue only
throw CommonExceptions.INVALID_REQUEST.toException()
    .detailIssue("password", "Must contain at least one uppercase letter");
```

## Jackson Configuration Properties

```yaml
f8a:
  common:
    jackson:
      enabled: true
      fail-on-unknown-properties: false
      write-dates-as-timestamps: false
      include-null-values: false
      write-enums-using-to-string: true
      read-enums-using-to-string: true
      property-naming-strategy: LOWER_CAMEL_CASE
      date-format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
      time-zone: UTC
```

## WebClient Configuration Properties

```yaml
f8a:
  common:
    webclient:
      enabled: true
      max-connections: 100
      connect-timeout: 10s
      read-timeout: 30s
      max-idle-time: 30s
      max-life-time: 5m
      pending-acquire-timeout: 45s
      connection-pool-name: summer-pool
```

## Logging Configuration

```yaml
f8a:
  common:
    logging:
      enabled: true
      aop:
        enabled: true
        log-headers: false
        log-request-body: false
        log-response-body: false
```

## Service Layer Error Handling Pattern

```java
@Service
@Slf4j
@RequiredArgsConstructor
public class UserService {

    public Mono<User> processUser(String userId) {
        return findUser(userId)
            .flatMap(this::enrichWithExternalData)
            .doOnSuccess(user -> log.info("User processed: {}", user.getId()))
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
                log.warn("Failed to enrich user data, continuing without", ex);
                return Mono.just(user); // Graceful degradation
            });
    }
}
```
