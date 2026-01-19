# WebFlux Patterns Reference

## Table of Contents
- [Annotated Controller Patterns](#annotated-controller-patterns)
- [Router Function Patterns](#router-function-patterns)
- [Handler Patterns](#handler-patterns)
- [WebClient Advanced Patterns](#webclient-advanced-patterns)
- [SSE and WebSocket Patterns](#sse-and-websocket-patterns)
- [Request/Response Processing](#requestresponse-processing)
- [Error Handling Strategies](#error-handling-strategies)
- [Filter Patterns](#filter-patterns)

---

## Annotated Controller Patterns

### Basic Controller with @RestController

```java
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
@Slf4j
public class UserController {

    private final UserService userService;

    // GET - Get all users
    @GetMapping
    public Flux<UserDto> getAllUsers() {
        return userService.findAll()
            .map(UserMapper::toDto);
    }

    // GET - Get user by ID
    @GetMapping("/{id}")
    public Mono<UserDto> getUserById(@PathVariable String id) {
        return userService.findById(id)
            .map(UserMapper::toDto)
            .switchIfEmpty(Mono.error(new NotFoundException("User not found: " + id)));
    }

    // POST - Create new user
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserDto> createUser(@Valid @RequestBody CreateUserRequest request) {
        return userService.create(request)
            .map(UserMapper::toDto);
    }

    // PUT - Update entire user
    @PutMapping("/{id}")
    public Mono<UserDto> updateUser(
            @PathVariable String id,
            @Valid @RequestBody UpdateUserRequest request) {
        return userService.update(id, request)
            .map(UserMapper::toDto);
    }

    // PATCH - Update partial user
    @PatchMapping("/{id}")
    public Mono<UserDto> patchUser(
            @PathVariable String id,
            @RequestBody Map<String, Object> updates) {
        return userService.patch(id, updates)
            .map(UserMapper::toDto);
    }

    // DELETE - Delete user
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteUser(@PathVariable String id) {
        return userService.deleteById(id);
    }
}
```

### @RequestMapping Advanced Options

```java
@RestController
@RequestMapping(
    path = "/api/v1/products",
    produces = MediaType.APPLICATION_JSON_VALUE
)
public class ProductController {

    // Multiple HTTP methods
    @RequestMapping(
        path = "/{id}",
        method = {RequestMethod.GET, RequestMethod.HEAD}
    )
    public Mono<Product> getProduct(@PathVariable String id) {
        return productService.findById(id);
    }

    // Consume specific content types
    @PostMapping(
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public Mono<Product> createProduct(@RequestBody CreateProductRequest request) {
        return productService.create(request);
    }

    // Multiple consumes types
    @PostMapping(
        path = "/import",
        consumes = {MediaType.APPLICATION_JSON_VALUE, "application/x-ndjson"}
    )
    public Flux<Product> importProducts(@RequestBody Flux<Product> products) {
        return productService.importAll(products);
    }

    // Request mapping with params condition
    @GetMapping(params = "category")
    public Flux<Product> getByCategory(@RequestParam String category) {
        return productService.findByCategory(category);
    }

    // Request mapping with headers condition
    @GetMapping(headers = "X-API-Version=2")
    public Flux<ProductV2Dto> getAllProductsV2() {
        return productService.findAllV2();
    }

    // Combine multiple conditions
    @PostMapping(
        path = "/bulk",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        headers = "X-Bulk-Operation=true"
    )
    public Flux<Product> bulkCreate(@RequestBody List<CreateProductRequest> requests) {
        return productService.bulkCreate(requests);
    }
}
```

### Path Variables and Patterns

```java
@RestController
@RequestMapping("/api/v1")
public class PathVariableController {

    // Basic path variable
    @GetMapping("/users/{userId}")
    public Mono<User> getUser(@PathVariable String userId) {
        return userService.findById(userId);
    }

    // Multiple path variables
    @GetMapping("/users/{userId}/orders/{orderId}")
    public Mono<Order> getUserOrder(
            @PathVariable String userId,
            @PathVariable String orderId) {
        return orderService.findByUserIdAndOrderId(userId, orderId);
    }

    // Path variable with regex pattern
    @GetMapping("/users/{id:\\d+}")  // Only match numeric
    public Mono<User> getUserByNumericId(@PathVariable Long id) {
        return userService.findById(id);
    }

    // Path variable with custom name
    @GetMapping("/products/{product-id}")
    public Mono<Product> getProduct(
            @PathVariable("product-id") String productId) {
        return productService.findById(productId);
    }

    // Optional path variable (Spring 4.3.3+)
    @GetMapping({"/categories", "/categories/{id}"})
    public Flux<Category> getCategories(
            @PathVariable(required = false) String id) {
        if (id != null) {
            return categoryService.findById(id).flux();
        }
        return categoryService.findAll();
    }

    // Wildcard patterns
    @GetMapping("/files/**")
    public Mono<Resource> getFile(ServerHttpRequest request) {
        String path = request.getPath().pathWithinApplication().value();
        String filePath = path.substring("/files/".length());
        return fileService.getFile(filePath);
    }

    // URI template variables
    @GetMapping("/search/{*query}")  // Capture remaining path
    public Flux<SearchResult> search(@PathVariable String query) {
        return searchService.search(query);
    }
}
```

### Query Parameters (@RequestParam)

```java
@RestController
@RequestMapping("/api/v1/products")
public class QueryParamController {

    // Basic query param
    @GetMapping("/search")
    public Flux<Product> search(@RequestParam String keyword) {
        return productService.search(keyword);
    }

    // Optional query param with default value
    @GetMapping
    public Flux<Product> getProducts(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "createdAt") String sortBy,
            @RequestParam(defaultValue = "desc") String sortDir) {

        Sort sort = sortDir.equalsIgnoreCase("asc")
            ? Sort.by(sortBy).ascending()
            : Sort.by(sortBy).descending();

        return productService.findAll(PageRequest.of(page, size, sort));
    }

    // Optional query param (can be null)
    @GetMapping("/filter")
    public Flux<Product> filter(
            @RequestParam(required = false) String category,
            @RequestParam(required = false) BigDecimal minPrice,
            @RequestParam(required = false) BigDecimal maxPrice,
            @RequestParam(required = false) Boolean inStock) {

        return productService.filter(ProductFilter.builder()
            .category(category)
            .minPrice(minPrice)
            .maxPrice(maxPrice)
            .inStock(inStock)
            .build());
    }

    // Multiple values (List/Array)
    @GetMapping("/by-ids")
    public Flux<Product> getByIds(@RequestParam List<String> ids) {
        return productService.findByIds(ids);
    }

    // Map all query params
    @GetMapping("/dynamic-search")
    public Flux<Product> dynamicSearch(@RequestParam Map<String, String> params) {
        return productService.dynamicSearch(params);
    }

    // Query param with custom name
    @GetMapping("/by-category")
    public Flux<Product> getByCategory(
            @RequestParam("cat") String category,
            @RequestParam("sub-cat") String subCategory) {
        return productService.findByCategory(category, subCategory);
    }

    // MultiValueMap for duplicate keys
    @GetMapping("/multi-filter")
    public Flux<Product> multiFilter(
            @RequestParam MultiValueMap<String, String> params) {
        // params.get("tag") returns List<String> for ?tag=a&tag=b&tag=c
        return productService.filterByMultipleValues(params);
    }
}
```

### Request Headers (@RequestHeader)

```java
@RestController
@RequestMapping("/api/v1")
public class HeaderController {

    // Required header
    @GetMapping("/protected")
    public Mono<Data> getProtectedData(
            @RequestHeader("Authorization") String authorization) {
        return dataService.getProtected(authorization);
    }

    // Optional header with default
    @GetMapping("/data")
    public Flux<Data> getData(
            @RequestHeader(value = "Accept-Language", defaultValue = "en") String language,
            @RequestHeader(value = "X-Request-ID", required = false) String requestId) {

        return dataService.getData(language)
            .contextWrite(ctx -> requestId != null
                ? ctx.put("requestId", requestId)
                : ctx);
    }

    // All headers as Map
    @GetMapping("/debug/headers")
    public Mono<Map<String, String>> getHeaders(
            @RequestHeader Map<String, String> headers) {
        return Mono.just(headers);
    }

    // HttpHeaders object
    @GetMapping("/info")
    public Mono<RequestInfo> getInfo(@RequestHeader HttpHeaders headers) {
        return Mono.just(RequestInfo.builder()
            .contentType(headers.getContentType())
            .acceptLanguage(headers.getAcceptLanguage())
            .userAgent(headers.getFirst(HttpHeaders.USER_AGENT))
            .build());
    }

    // API versioning via header
    @GetMapping("/resource")
    public Mono<ResponseEntity<?>> getResource(
            @RequestHeader(value = "X-API-Version", defaultValue = "1") int version) {

        return switch (version) {
            case 1 -> resourceService.getV1().map(ResponseEntity::ok);
            case 2 -> resourceService.getV2().map(ResponseEntity::ok);
            default -> Mono.just(ResponseEntity.badRequest()
                .body("Unsupported API version: " + version));
        };
    }

    // Conditional processing based on headers
    @GetMapping("/content")
    public Mono<ResponseEntity<byte[]>> getContent(
            @RequestHeader(value = HttpHeaders.IF_NONE_MATCH, required = false) String ifNoneMatch,
            @RequestHeader(value = HttpHeaders.IF_MODIFIED_SINCE, required = false)
                @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant ifModifiedSince) {

        return contentService.getWithETag()
            .flatMap(content -> {
                if (ifNoneMatch != null && ifNoneMatch.equals(content.getEtag())) {
                    return Mono.just(ResponseEntity.status(HttpStatus.NOT_MODIFIED).build());
                }
                if (ifModifiedSince != null && !content.getLastModified().isAfter(ifModifiedSince)) {
                    return Mono.just(ResponseEntity.status(HttpStatus.NOT_MODIFIED).build());
                }
                return Mono.just(ResponseEntity.ok()
                    .eTag(content.getEtag())
                    .lastModified(content.getLastModified())
                    .body(content.getData()));
            });
    }
}
```

### Request Body (@RequestBody)

```java
@RestController
@RequestMapping("/api/v1/orders")
public class RequestBodyController {

    // JSON body
    @PostMapping
    public Mono<Order> createOrder(@Valid @RequestBody CreateOrderRequest request) {
        return orderService.create(request);
    }

    // Reactive body - streaming JSON
    @PostMapping(
        path = "/batch",
        consumes = "application/x-ndjson"  // Newline-delimited JSON
    )
    public Flux<OrderResult> processBatch(@RequestBody Flux<CreateOrderRequest> requests) {
        return requests
            .flatMap(orderService::create)
            .map(order -> OrderResult.success(order.getId()))
            .onErrorResume(e -> Mono.just(OrderResult.error(e.getMessage())));
    }

    // Raw body as String
    @PostMapping(path = "/webhook", consumes = MediaType.TEXT_PLAIN_VALUE)
    public Mono<Void> handleWebhook(@RequestBody String payload) {
        return webhookService.process(payload);
    }

    // Raw body as byte[]
    @PostMapping(path = "/binary", consumes = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    public Mono<String> processBinary(@RequestBody byte[] data) {
        return binaryService.process(data);
    }

    // Body with custom deserialization
    @PostMapping("/custom")
    public Mono<Response> processCustom(
            @RequestBody Mono<CustomRequest> requestMono) {
        return requestMono
            .flatMap(customService::process);
    }

    // Optional body
    @PatchMapping("/{id}")
    public Mono<Order> patchOrder(
            @PathVariable String id,
            @RequestBody(required = false) Map<String, Object> updates) {

        if (updates == null || updates.isEmpty()) {
            return orderService.findById(id);
        }
        return orderService.patch(id, updates);
    }

    // Body validation with custom validator
    @PostMapping("/validated")
    public Mono<Order> createValidatedOrder(
            @RequestBody @Validated(OnCreate.class) CreateOrderRequest request) {
        return orderService.create(request);
    }
}
```

### Cookie and Session (@CookieValue)

```java
@RestController
@RequestMapping("/api/v1")
public class CookieController {

    // Read cookie
    @GetMapping("/preferences")
    public Mono<UserPreferences> getPreferences(
            @CookieValue(value = "user-prefs", required = false) String prefsJson) {

        if (prefsJson == null) {
            return Mono.just(UserPreferences.defaults());
        }
        return Mono.just(objectMapper.readValue(prefsJson, UserPreferences.class));
    }

    // Set cookie in response
    @PostMapping("/preferences")
    public Mono<ResponseEntity<Void>> savePreferences(
            @RequestBody UserPreferences preferences) {

        String prefsJson = objectMapper.writeValueAsString(preferences);

        ResponseCookie cookie = ResponseCookie.from("user-prefs", prefsJson)
            .httpOnly(true)
            .secure(true)
            .path("/")
            .maxAge(Duration.ofDays(30))
            .sameSite("Strict")
            .build();

        return Mono.just(ResponseEntity.ok()
            .header(HttpHeaders.SET_COOKIE, cookie.toString())
            .build());
    }

    // Session ID from cookie
    @GetMapping("/session")
    public Mono<SessionInfo> getSessionInfo(
            @CookieValue("SESSIONID") String sessionId) {
        return sessionService.getSession(sessionId);
    }

    // Multiple cookies
    @GetMapping("/context")
    public Mono<UserContext> getUserContext(
            @CookieValue(value = "auth-token", required = false) String authToken,
            @CookieValue(value = "refresh-token", required = false) String refreshToken,
            @CookieValue(value = "theme", defaultValue = "light") String theme) {

        return userContextService.build(authToken, refreshToken, theme);
    }
}
```

### Response Handling and Status Codes

```java
@RestController
@RequestMapping("/api/v1/resources")
public class ResponseController {

    // ResponseEntity with custom status and headers
    @PostMapping
    public Mono<ResponseEntity<Resource>> createResource(
            @RequestBody CreateResourceRequest request) {

        return resourceService.create(request)
            .map(resource -> ResponseEntity
                .created(URI.create("/api/v1/resources/" + resource.getId()))
                .header("X-Resource-Version", String.valueOf(resource.getVersion()))
                .body(resource));
    }

    // Conditional response
    @GetMapping("/{id}")
    public Mono<ResponseEntity<Resource>> getResource(@PathVariable String id) {
        return resourceService.findById(id)
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    // No content response
    @DeleteMapping("/{id}")
    public Mono<ResponseEntity<Void>> deleteResource(@PathVariable String id) {
        return resourceService.deleteById(id)
            .then(Mono.just(ResponseEntity.noContent().<Void>build()))
            .onErrorReturn(NotFoundException.class,
                ResponseEntity.notFound().build());
    }

    // Accepted (async processing)
    @PostMapping("/async-process")
    public Mono<ResponseEntity<ProcessingResponse>> asyncProcess(
            @RequestBody ProcessRequest request) {

        return processingService.submitForProcessing(request)
            .map(jobId -> ResponseEntity
                .accepted()
                .header("Location", "/api/v1/jobs/" + jobId)
                .body(new ProcessingResponse(jobId, "PENDING")));
    }

    // Response with ETag and caching headers
    @GetMapping("/{id}/cacheable")
    public Mono<ResponseEntity<Resource>> getCacheableResource(@PathVariable String id) {
        return resourceService.findById(id)
            .map(resource -> {
                String etag = "\"" + resource.getVersion() + "\"";
                return ResponseEntity.ok()
                    .eTag(etag)
                    .cacheControl(CacheControl.maxAge(Duration.ofHours(1)))
                    .lastModified(resource.getUpdatedAt())
                    .body(resource);
            });
    }

    // Streaming response
    @GetMapping(value = "/stream", produces = MediaType.APPLICATION_NDJSON_VALUE)
    public Flux<Resource> streamResources() {
        return resourceService.streamAll()
            .delayElements(Duration.ofMillis(100));  // Simulate streaming
    }

    // Download file
    @GetMapping("/{id}/download")
    public Mono<ResponseEntity<Resource>> downloadResource(@PathVariable String id) {
        return resourceService.getFileResource(id)
            .map(file -> ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(file.getContentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"" + file.getFilename() + "\"")
                .body(file.getResource()));
    }

    // Error responses
    @GetMapping("/{id}/strict")
    public Mono<ResponseEntity<Resource>> getResourceStrict(@PathVariable String id) {
        return resourceService.findById(id)
            .map(ResponseEntity::ok)
            .switchIfEmpty(Mono.just(ResponseEntity
                .status(HttpStatus.NOT_FOUND)
                .header("X-Error-Code", "RESOURCE_NOT_FOUND")
                .build()));
    }
}
```

### Validation với Bean Validation

```java
@RestController
@RequestMapping("/api/v1/users")
@Validated
public class ValidationController {

    // Basic validation
    @PostMapping
    public Mono<User> createUser(@Valid @RequestBody CreateUserRequest request) {
        return userService.create(request);
    }

    // Path variable validation
    @GetMapping("/{id}")
    public Mono<User> getUser(
            @PathVariable @Pattern(regexp = "^[a-f0-9]{24}$") String id) {
        return userService.findById(id);
    }

    // Query param validation
    @GetMapping("/search")
    public Flux<User> searchUsers(
            @RequestParam @NotBlank @Size(min = 2, max = 100) String query,
            @RequestParam @Min(0) @Max(1000) int limit) {
        return userService.search(query, limit);
    }

    // Validation groups
    @PostMapping("/register")
    public Mono<User> register(
            @Validated(OnRegistration.class) @RequestBody UserRegistrationRequest request) {
        return userService.register(request);
    }

    @PutMapping("/{id}")
    public Mono<User> updateUser(
            @PathVariable String id,
            @Validated(OnUpdate.class) @RequestBody UpdateUserRequest request) {
        return userService.update(id, request);
    }

    // Custom constraint validation
    @PostMapping("/with-custom")
    public Mono<User> createWithCustomValidation(
            @Valid @RequestBody @UniqueEmail CreateUserRequest request) {
        return userService.create(request);
    }
}

// Request DTOs with validation
@Data
public class CreateUserRequest {

    @NotBlank(message = "Email is required")
    @Email(message = "Invalid email format")
    private String email;

    @NotBlank(message = "Username is required")
    @Size(min = 3, max = 50, message = "Username must be 3-50 characters")
    @Pattern(regexp = "^[a-zA-Z0-9_]+$", message = "Username can only contain letters, numbers, and underscores")
    private String username;

    @NotBlank(message = "Password is required", groups = OnRegistration.class)
    @Size(min = 8, message = "Password must be at least 8 characters")
    @Pattern(
        regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).*$",
        message = "Password must contain uppercase, lowercase, and digit"
    )
    private String password;

    @NotNull(message = "Birth date is required")
    @Past(message = "Birth date must be in the past")
    private LocalDate birthDate;

    @Valid  // Validate nested object
    @NotNull
    private AddressDto address;
}

@Data
public class AddressDto {
    @NotBlank
    private String street;

    @NotBlank
    private String city;

    @NotBlank
    @Pattern(regexp = "^\\d{5}$")
    private String zipCode;
}

// Validation groups
public interface OnRegistration {}
public interface OnUpdate {}

// Custom validator
@Target({ElementType.TYPE, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = UniqueEmailValidator.class)
public @interface UniqueEmail {
    String message() default "Email already exists";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

@Component
@RequiredArgsConstructor
public class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, CreateUserRequest> {

    private final UserRepository userRepository;

    @Override
    public boolean isValid(CreateUserRequest request, ConstraintValidatorContext context) {
        if (request == null || request.getEmail() == null) {
            return true;
        }
        return !userRepository.existsByEmail(request.getEmail()).block();
    }
}
```

### Exception Handling với @ExceptionHandler

```java
@RestController
@RequestMapping("/api/v1/orders")
public class OrderController {

    @PostMapping
    public Mono<Order> createOrder(@Valid @RequestBody CreateOrderRequest request) {
        return orderService.create(request);
    }

    // Local exception handler
    @ExceptionHandler(InsufficientStockException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public Mono<ErrorResponse> handleInsufficientStock(InsufficientStockException ex) {
        return Mono.just(ErrorResponse.builder()
            .code("INSUFFICIENT_STOCK")
            .message(ex.getMessage())
            .details(Map.of(
                "productId", ex.getProductId(),
                "requested", ex.getRequestedQuantity(),
                "available", ex.getAvailableQuantity()
            ))
            .build());
    }
}

// Global exception handler
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Mono<ErrorResponse> handleValidationErrors(MethodArgumentNotValidException ex) {
        Map<String, String> errors = ex.getBindingResult().getFieldErrors().stream()
            .collect(Collectors.toMap(
                FieldError::getField,
                error -> error.getDefaultMessage() != null ? error.getDefaultMessage() : "Invalid value",
                (a, b) -> a + "; " + b
            ));

        return Mono.just(ErrorResponse.builder()
            .code("VALIDATION_ERROR")
            .message("Validation failed")
            .details(errors)
            .timestamp(Instant.now())
            .build());
    }

    @ExceptionHandler(ConstraintViolationException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Mono<ErrorResponse> handleConstraintViolation(ConstraintViolationException ex) {
        Map<String, String> errors = ex.getConstraintViolations().stream()
            .collect(Collectors.toMap(
                v -> v.getPropertyPath().toString(),
                ConstraintViolation::getMessage,
                (a, b) -> a + "; " + b
            ));

        return Mono.just(ErrorResponse.builder()
            .code("CONSTRAINT_VIOLATION")
            .message("Request validation failed")
            .details(errors)
            .build());
    }

    @ExceptionHandler(NotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Mono<ErrorResponse> handleNotFound(NotFoundException ex) {
        return Mono.just(ErrorResponse.builder()
            .code("NOT_FOUND")
            .message(ex.getMessage())
            .build());
    }

    @ExceptionHandler(DuplicateKeyException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public Mono<ErrorResponse> handleDuplicateKey(DuplicateKeyException ex) {
        return Mono.just(ErrorResponse.builder()
            .code("DUPLICATE_ENTRY")
            .message("Resource already exists")
            .build());
    }

    @ExceptionHandler(WebExchangeBindException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Mono<ErrorResponse> handleBindException(WebExchangeBindException ex) {
        Map<String, String> errors = ex.getFieldErrors().stream()
            .collect(Collectors.toMap(
                FieldError::getField,
                error -> error.getDefaultMessage() != null ? error.getDefaultMessage() : "Invalid",
                (a, b) -> a + "; " + b
            ));

        return Mono.just(ErrorResponse.builder()
            .code("BINDING_ERROR")
            .message("Failed to bind request")
            .details(errors)
            .build());
    }

    @ExceptionHandler(ResponseStatusException.class)
    public Mono<ResponseEntity<ErrorResponse>> handleResponseStatus(ResponseStatusException ex) {
        return Mono.just(ResponseEntity
            .status(ex.getStatusCode())
            .body(ErrorResponse.builder()
                .code("HTTP_ERROR")
                .message(ex.getReason())
                .build()));
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public Mono<ErrorResponse> handleGenericException(Exception ex) {
        log.error("Unexpected error", ex);
        return Mono.just(ErrorResponse.builder()
            .code("INTERNAL_ERROR")
            .message("An unexpected error occurred")
            .build());
    }
}

@Data
@Builder
public class ErrorResponse {
    private String code;
    private String message;
    private Object details;
    @Builder.Default
    private Instant timestamp = Instant.now();
}
```

### Content Negotiation

```java
@RestController
@RequestMapping("/api/v1/reports")
public class ContentNegotiationController {

    // Produce multiple formats based on Accept header
    @GetMapping(
        path = "/{id}",
        produces = {
            MediaType.APPLICATION_JSON_VALUE,
            MediaType.APPLICATION_XML_VALUE,
            "text/csv"
        }
    )
    public Mono<Report> getReport(@PathVariable String id) {
        return reportService.findById(id);
    }

    // Different methods for different content types
    @GetMapping(path = "/summary", produces = MediaType.APPLICATION_JSON_VALUE)
    public Mono<ReportSummary> getSummaryJson() {
        return reportService.getSummary();
    }

    @GetMapping(path = "/summary", produces = "text/csv")
    public Mono<String> getSummaryCsv() {
        return reportService.getSummary()
            .map(this::convertToCsv);
    }

    @GetMapping(path = "/summary", produces = MediaType.APPLICATION_PDF_VALUE)
    public Mono<byte[]> getSummaryPdf() {
        return reportService.getSummary()
            .map(pdfGenerator::generate);
    }

    // Custom media type
    @GetMapping(
        path = "/custom",
        produces = "application/vnd.myapp.report.v2+json"
    )
    public Mono<ReportV2> getCustomFormat() {
        return reportService.getReportV2();
    }

    // ResponseEntity with dynamic content type
    @GetMapping("/{id}/download")
    public Mono<ResponseEntity<byte[]>> downloadReport(
            @PathVariable String id,
            @RequestParam(defaultValue = "pdf") String format) {

        return reportService.findById(id)
            .flatMap(report -> generateReport(report, format))
            .map(data -> {
                MediaType mediaType = switch (format) {
                    case "pdf" -> MediaType.APPLICATION_PDF;
                    case "xlsx" -> MediaType.parseMediaType(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
                    case "csv" -> MediaType.parseMediaType("text/csv");
                    default -> MediaType.APPLICATION_OCTET_STREAM;
                };

                return ResponseEntity.ok()
                    .contentType(mediaType)
                    .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"report." + format + "\"")
                    .body(data);
            });
    }
}
```

### Controller Advice and Model Attributes

```java
@ControllerAdvice
public class GlobalControllerAdvice {

    // Add common attributes to all controllers
    @ModelAttribute
    public void addCommonAttributes(Model model, ServerWebExchange exchange) {
        model.addAttribute("requestId", exchange.getRequest().getId());
        model.addAttribute("timestamp", Instant.now());
    }

    // Bind custom types
    @InitBinder
    public void initBinder(WebDataBinder binder) {
        binder.registerCustomEditor(LocalDate.class, new PropertyEditorSupport() {
            @Override
            public void setAsText(String text) {
                setValue(LocalDate.parse(text, DateTimeFormatter.ISO_DATE));
            }
        });
    }
}

// Scoped controller advice
@RestControllerAdvice(
    basePackages = "com.example.api.admin",
    annotations = AdminController.class
)
public class AdminControllerAdvice {

    @ExceptionHandler(AdminException.class)
    @ResponseStatus(HttpStatus.FORBIDDEN)
    public Mono<ErrorResponse> handleAdminException(AdminException ex) {
        return Mono.just(ErrorResponse.builder()
            .code("ADMIN_ERROR")
            .message(ex.getMessage())
            .build());
    }
}

@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@RestController
@RequestMapping("/api/admin")
public @interface AdminController {
}
```

### Cross-Origin Requests (@CrossOrigin)

```java
@RestController
@RequestMapping("/api/v1/public")
@CrossOrigin(
    origins = {"https://example.com", "https://app.example.com"},
    methods = {RequestMethod.GET, RequestMethod.POST},
    allowedHeaders = {"Content-Type", "Authorization"},
    exposedHeaders = {"X-Custom-Header"},
    allowCredentials = "true",
    maxAge = 3600
)
public class PublicApiController {

    @GetMapping("/data")
    public Flux<Data> getData() {
        return dataService.findAll();
    }

    // Override class-level CORS for specific endpoint
    @CrossOrigin(origins = "*", maxAge = 1800)
    @GetMapping("/open-data")
    public Flux<Data> getOpenData() {
        return dataService.findPublic();
    }

    // Disable CORS for specific endpoint
    @CrossOrigin(origins = {})
    @GetMapping("/restricted")
    public Mono<Data> getRestricted() {
        return dataService.findRestricted();
    }
}
```

---

## Router Function Patterns

### Nested Routes

```java
@Configuration
public class ApiRouter {

    @Bean
    public RouterFunction<ServerResponse> apiRoutes(
            UserHandler userHandler,
            OrderHandler orderHandler,
            ProductHandler productHandler) {

        return RouterFunctions.route()
            .path("/api/v1", builder -> builder
                .nest(path("/users"), this::userRoutes)
                .nest(path("/orders"), this::orderRoutes)
                .nest(path("/products"), this::productRoutes)
            )
            .filter(this::loggingFilter)
            .filter(this::errorHandlingFilter)
            .build();
    }

    private RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .GET("", handler::listUsers)
            .GET("/{id}", handler::getUser)
            .POST("", contentType(APPLICATION_JSON), handler::createUser)
            .PUT("/{id}", contentType(APPLICATION_JSON), handler::updateUser)
            .DELETE("/{id}", handler::deleteUser)
            .nest(path("/{userId}/orders"), builder -> builder
                .GET("", handler::getUserOrders)
                .GET("/{orderId}", handler::getUserOrder)
            )
            .build();
    }

    private RequestPredicate path(String pattern) {
        return RequestPredicates.path(pattern);
    }

    private RequestPredicate contentType(MediaType mediaType) {
        return RequestPredicates.contentType(mediaType);
    }
}
```

### Conditional Routes

```java
@Bean
public RouterFunction<ServerResponse> conditionalRoutes(
        FeatureFlagService featureFlags,
        LegacyHandler legacyHandler,
        NewHandler newHandler) {

    return RouterFunctions.route()
        .path("/api/process", builder -> {
            if (featureFlags.isEnabled("new-processor")) {
                builder.POST("", newHandler::process);
            } else {
                builder.POST("", legacyHandler::process);
            }
        })
        .build();
}

// Dynamic routing based on request
@Bean
public RouterFunction<ServerResponse> dynamicRoutes() {
    return RouterFunctions.route()
        .route(
            RequestPredicates.GET("/api/data")
                .and(request -> request.headers().header("X-Version").contains("v2")),
            this::handleV2
        )
        .route(
            RequestPredicates.GET("/api/data"),
            this::handleV1
        )
        .build();
}
```

### Route Composition

```java
@Configuration
public class ComposedRouterConfig {

    @Bean
    public RouterFunction<ServerResponse> composedRoutes(
            List<ApiRouterContributor> contributors) {

        RouterFunction<ServerResponse> routes = RouterFunctions.route()
            .GET("/health", request -> ServerResponse.ok().bodyValue("OK"))
            .build();

        for (ApiRouterContributor contributor : contributors) {
            routes = routes.and(contributor.routes());
        }

        return routes;
    }
}

public interface ApiRouterContributor {
    RouterFunction<ServerResponse> routes();
}

@Component
@Order(1)
public class UserApiContributor implements ApiRouterContributor {

    private final UserHandler handler;

    @Override
    public RouterFunction<ServerResponse> routes() {
        return RouterFunctions.route()
            .path("/api/users", builder -> builder
                .GET("", handler::list)
                .GET("/{id}", handler::get)
                .POST("", handler::create)
            )
            .build();
    }
}
```

## Handler Patterns

### Request Validation Handler

```java
@Component
@RequiredArgsConstructor
public class ValidatingHandler {

    private final Validator validator;
    private final UserService userService;

    public Mono<ServerResponse> createUser(ServerRequest request) {
        return request.bodyToMono(CreateUserRequest.class)
            .flatMap(this::validate)
            .flatMap(userService::create)
            .flatMap(user -> ServerResponse
                .created(URI.create("/api/users/" + user.getId()))
                .bodyValue(user))
            .onErrorResume(ValidationException.class, this::handleValidationError);
    }

    private <T> Mono<T> validate(T object) {
        Set<ConstraintViolation<T>> violations = validator.validate(object);
        if (violations.isEmpty()) {
            return Mono.just(object);
        }

        Map<String, String> errors = violations.stream()
            .collect(Collectors.toMap(
                v -> v.getPropertyPath().toString(),
                ConstraintViolation::getMessage,
                (a, b) -> a + "; " + b
            ));

        return Mono.error(new ValidationException(errors));
    }

    private Mono<ServerResponse> handleValidationError(ValidationException ex) {
        return ServerResponse.badRequest()
            .bodyValue(ErrorResponse.builder()
                .code("VALIDATION_ERROR")
                .message("Validation failed")
                .details(ex.getErrors())
                .build());
    }
}
```

### Pagination Handler

```java
@Component
public class PaginatedHandler {

    private static final int DEFAULT_PAGE = 0;
    private static final int DEFAULT_SIZE = 20;
    private static final int MAX_SIZE = 100;

    public Mono<ServerResponse> listUsers(ServerRequest request) {
        int page = request.queryParam("page")
            .map(Integer::parseInt)
            .orElse(DEFAULT_PAGE);

        int size = request.queryParam("size")
            .map(Integer::parseInt)
            .map(s -> Math.min(s, MAX_SIZE))
            .orElse(DEFAULT_SIZE);

        String sortBy = request.queryParam("sort").orElse("createdAt");
        String direction = request.queryParam("dir").orElse("desc");

        Sort sort = direction.equalsIgnoreCase("asc")
            ? Sort.by(sortBy).ascending()
            : Sort.by(sortBy).descending();

        PageRequest pageRequest = PageRequest.of(page, size, sort);

        return userService.findAll(pageRequest)
            .collectList()
            .zipWith(userService.count())
            .flatMap(tuple -> {
                List<UserDto> users = tuple.getT1();
                long total = tuple.getT2();

                PageResponse<UserDto> response = PageResponse.<UserDto>builder()
                    .content(users)
                    .page(page)
                    .size(size)
                    .totalElements(total)
                    .totalPages((int) Math.ceil((double) total / size))
                    .build();

                return ServerResponse.ok()
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(response);
            });
    }
}
```

### File Upload Handler

```java
@Component
@RequiredArgsConstructor
public class FileUploadHandler {

    private final FileStorageService storageService;
    private final long maxFileSize = 10 * 1024 * 1024; // 10MB

    public Mono<ServerResponse> uploadFile(ServerRequest request) {
        return request.multipartData()
            .flatMap(parts -> {
                Map<String, Part> partMap = parts.toSingleValueMap();
                Part filePart = partMap.get("file");

                if (filePart == null) {
                    return Mono.error(new BadRequestException("No file provided"));
                }

                if (!(filePart instanceof FilePart)) {
                    return Mono.error(new BadRequestException("Invalid file part"));
                }

                FilePart file = (FilePart) filePart;
                return validateAndStore(file);
            })
            .flatMap(fileInfo -> ServerResponse
                .created(URI.create("/api/files/" + fileInfo.getId()))
                .bodyValue(fileInfo));
    }

    private Mono<FileInfo> validateAndStore(FilePart file) {
        return DataBufferUtils.join(file.content())
            .flatMap(dataBuffer -> {
                long size = dataBuffer.readableByteCount();
                if (size > maxFileSize) {
                    DataBufferUtils.release(dataBuffer);
                    return Mono.error(new BadRequestException(
                        "File too large. Max size: " + maxFileSize));
                }

                String contentType = file.headers().getContentType() != null
                    ? file.headers().getContentType().toString()
                    : "application/octet-stream";

                return storageService.store(
                    file.filename(),
                    contentType,
                    dataBuffer.asInputStream()
                );
            });
    }

    public Mono<ServerResponse> downloadFile(ServerRequest request) {
        String fileId = request.pathVariable("id");

        return storageService.getFile(fileId)
            .flatMap(file -> ServerResponse.ok()
                .contentType(MediaType.parseMediaType(file.getContentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"" + file.getFilename() + "\"")
                .body(file.getContent(), DataBuffer.class))
            .switchIfEmpty(ServerResponse.notFound().build());
    }
}
```

## WebClient Advanced Patterns

### Connection Pool Configuration

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient webClient() {
        // Connection provider with pool configuration
        ConnectionProvider provider = ConnectionProvider.builder("custom-pool")
            .maxConnections(500)
            .maxIdleTime(Duration.ofSeconds(20))
            .maxLifeTime(Duration.ofSeconds(60))
            .pendingAcquireTimeout(Duration.ofSeconds(60))
            .pendingAcquireMaxCount(1000)
            .evictInBackground(Duration.ofSeconds(120))
            .metrics(true)
            .build();

        // HTTP client with connection provider
        HttpClient httpClient = HttpClient.create(provider)
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 5000)
            .responseTimeout(Duration.ofSeconds(30))
            .doOnConnected(conn -> conn
                .addHandlerLast(new ReadTimeoutHandler(30))
                .addHandlerLast(new WriteTimeoutHandler(30)));

        return WebClient.builder()
            .clientConnector(new ReactorClientHttpConnector(httpClient))
            .codecs(configurer -> configurer
                .defaultCodecs()
                .maxInMemorySize(16 * 1024 * 1024))
            .build();
    }
}
```

### Request/Response Logging

```java
@Component
@Slf4j
public class LoggingWebClientCustomizer {

    public WebClient.Builder customize(WebClient.Builder builder) {
        return builder
            .filter(logRequest())
            .filter(logResponse());
    }

    private ExchangeFilterFunction logRequest() {
        return ExchangeFilterFunction.ofRequestProcessor(request -> {
            log.debug("Request: {} {} Headers: {}",
                request.method(),
                request.url(),
                request.headers().entrySet().stream()
                    .filter(e -> !e.getKey().equalsIgnoreCase("Authorization"))
                    .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue)));
            return Mono.just(request);
        });
    }

    private ExchangeFilterFunction logResponse() {
        return ExchangeFilterFunction.ofResponseProcessor(response -> {
            log.debug("Response: {} Headers: {}",
                response.statusCode(),
                response.headers().asHttpHeaders());
            return Mono.just(response);
        });
    }
}
```

### OAuth2 Token Management

```java
@Service
@RequiredArgsConstructor
public class OAuth2WebClient {

    private final WebClient webClient;
    private final OAuth2TokenService tokenService;

    public <T> Mono<T> get(String uri, Class<T> responseType) {
        return executeWithToken(client -> client.get()
            .uri(uri)
            .retrieve()
            .bodyToMono(responseType));
    }

    public <T, R> Mono<R> post(String uri, T body, Class<R> responseType) {
        return executeWithToken(client -> client.post()
            .uri(uri)
            .bodyValue(body)
            .retrieve()
            .bodyToMono(responseType));
    }

    private <T> Mono<T> executeWithToken(Function<WebClient, Mono<T>> requestFunction) {
        return tokenService.getAccessToken()
            .flatMap(token -> {
                WebClient authenticatedClient = webClient.mutate()
                    .defaultHeader(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                    .build();
                return requestFunction.apply(authenticatedClient);
            })
            .retryWhen(Retry.backoff(1, Duration.ofMillis(100))
                .filter(e -> e instanceof UnauthorizedException)
                .doBeforeRetry(signal -> tokenService.refreshToken()));
    }
}

@Service
public class OAuth2TokenService {

    private final WebClient tokenClient;
    private final OAuth2Properties properties;
    private final AtomicReference<TokenInfo> tokenCache = new AtomicReference<>();

    public Mono<String> getAccessToken() {
        TokenInfo cached = tokenCache.get();
        if (cached != null && !cached.isExpired()) {
            return Mono.just(cached.getAccessToken());
        }

        return fetchNewToken()
            .map(token -> {
                tokenCache.set(token);
                return token.getAccessToken();
            });
    }

    public void refreshToken() {
        tokenCache.set(null);
    }

    private Mono<TokenInfo> fetchNewToken() {
        return tokenClient.post()
            .uri(properties.getTokenUri())
            .contentType(MediaType.APPLICATION_FORM_URLENCODED)
            .body(BodyInserters
                .fromFormData("grant_type", "client_credentials")
                .with("client_id", properties.getClientId())
                .with("client_secret", properties.getClientSecret()))
            .retrieve()
            .bodyToMono(TokenResponse.class)
            .map(response -> TokenInfo.builder()
                .accessToken(response.getAccessToken())
                .expiresAt(Instant.now().plusSeconds(response.getExpiresIn() - 60))
                .build());
    }
}
```

### Parallel Requests

```java
@Service
public class AggregationService {

    private final WebClient webClient;

    public Mono<AggregatedResponse> fetchAll(String userId) {
        Mono<UserProfile> profileMono = webClient.get()
            .uri("/users/{id}/profile", userId)
            .retrieve()
            .bodyToMono(UserProfile.class)
            .timeout(Duration.ofSeconds(5));

        Mono<List<Order>> ordersMono = webClient.get()
            .uri("/users/{id}/orders", userId)
            .retrieve()
            .bodyToFlux(Order.class)
            .collectList()
            .timeout(Duration.ofSeconds(5));

        Mono<UserPreferences> preferencesMono = webClient.get()
            .uri("/users/{id}/preferences", userId)
            .retrieve()
            .bodyToMono(UserPreferences.class)
            .timeout(Duration.ofSeconds(5))
            .onErrorReturn(UserPreferences.defaults());

        return Mono.zip(profileMono, ordersMono, preferencesMono)
            .map(tuple -> AggregatedResponse.builder()
                .profile(tuple.getT1())
                .orders(tuple.getT2())
                .preferences(tuple.getT3())
                .build());
    }

    // With error isolation
    public Mono<AggregatedResponse> fetchAllResilient(String userId) {
        Mono<Optional<UserProfile>> profileMono = fetchProfile(userId)
            .map(Optional::of)
            .onErrorReturn(Optional.empty());

        Mono<List<Order>> ordersMono = fetchOrders(userId)
            .onErrorReturn(Collections.emptyList());

        return Mono.zip(profileMono, ordersMono)
            .map(tuple -> AggregatedResponse.builder()
                .profile(tuple.getT1().orElse(null))
                .orders(tuple.getT2())
                .build());
    }
}
```

## SSE and WebSocket Patterns

### Advanced SSE with Heartbeat and Reconnection

```java
@RestController
@RequiredArgsConstructor
public class SSEController {

    private final EventService eventService;

    @GetMapping(value = "/events/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<?>> eventStream(
            @RequestParam String userId,
            @RequestHeader(value = "Last-Event-ID", required = false) String lastEventId) {

        // Resume from last event if reconnecting
        Flux<Event> events = lastEventId != null
            ? eventService.getEventsAfter(userId, lastEventId)
            : eventService.getEvents(userId);

        Flux<ServerSentEvent<Event>> eventFlux = events
            .map(event -> ServerSentEvent.<Event>builder()
                .id(event.getId())
                .event(event.getType())
                .data(event)
                .build());

        // Heartbeat every 30 seconds
        Flux<ServerSentEvent<?>> heartbeat = Flux.interval(Duration.ofSeconds(30))
            .map(i -> ServerSentEvent.builder()
                .event("heartbeat")
                .comment("keep-alive")
                .build());

        return Flux.merge(eventFlux, heartbeat)
            .doOnCancel(() -> eventService.unsubscribe(userId))
            .doOnError(e -> log.error("SSE error for user {}", userId, e));
    }
}
```

### WebSocket with STOMP

```java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic", "/queue");
        config.setApplicationDestinationPrefixes("/app");
        config.setUserDestinationPrefix("/user");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws")
            .setAllowedOrigins("*")
            .withSockJS();
    }
}

@Controller
@RequiredArgsConstructor
public class ChatController {

    private final SimpMessagingTemplate messagingTemplate;
    private final ChatService chatService;

    @MessageMapping("/chat.send")
    public void sendMessage(ChatMessage message, Principal principal) {
        message.setSender(principal.getName());
        message.setTimestamp(Instant.now());

        chatService.saveMessage(message)
            .doOnSuccess(saved -> {
                if (message.isPrivate()) {
                    messagingTemplate.convertAndSendToUser(
                        message.getRecipient(),
                        "/queue/messages",
                        saved
                    );
                } else {
                    messagingTemplate.convertAndSend(
                        "/topic/chat." + message.getRoomId(),
                        saved
                    );
                }
            })
            .subscribe();
    }

    @MessageMapping("/chat.typing")
    public void handleTyping(TypingEvent event, Principal principal) {
        event.setUser(principal.getName());
        messagingTemplate.convertAndSend(
            "/topic/chat." + event.getRoomId() + ".typing",
            event
        );
    }
}
```

### Raw WebSocket with Binary Data

```java
@Component
public class BinaryWebSocketHandler implements WebSocketHandler {

    private final DataProcessor dataProcessor;

    @Override
    public Mono<Void> handle(WebSocketSession session) {
        Flux<WebSocketMessage> output = session.receive()
            .filter(msg -> msg.getType() == WebSocketMessage.Type.BINARY)
            .flatMap(msg -> processMessage(msg.getPayload()))
            .map(result -> session.binaryMessage(factory ->
                factory.wrap(result)));

        return session.send(output)
            .doOnError(e -> log.error("WebSocket error", e))
            .doFinally(signal -> log.info("WebSocket closed: {}", signal));
    }

    private Mono<byte[]> processMessage(DataBuffer buffer) {
        byte[] data = new byte[buffer.readableByteCount()];
        buffer.read(data);
        DataBufferUtils.release(buffer);

        return dataProcessor.process(data);
    }
}
```

## Request/Response Processing

### Custom Argument Resolver

```java
@Configuration
public class WebFluxConfig implements WebFluxConfigurer {

    @Override
    public void configureArgumentResolvers(ArgumentResolverConfigurer configurer) {
        configurer.addCustomResolver(new CurrentUserArgumentResolver());
        configurer.addCustomResolver(new PageableArgumentResolver());
    }
}

public class CurrentUserArgumentResolver implements HandlerMethodArgumentResolver {

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.hasParameterAnnotation(CurrentUser.class)
            && parameter.getParameterType().equals(User.class);
    }

    @Override
    public Mono<Object> resolveArgument(
            MethodParameter parameter,
            BindingContext bindingContext,
            ServerWebExchange exchange) {

        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(auth -> (User) auth.getPrincipal());
    }
}

@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
public @interface CurrentUser {
}

// Usage
@GetMapping("/me")
public Mono<UserDto> getCurrentUser(@CurrentUser User user) {
    return Mono.just(UserMapper.toDto(user));
}
```

### Custom Response Handling

```java
@RestControllerAdvice
public class ResponseWrapper implements ResponseBodyResultHandler {

    @Override
    public Mono<Void> handleResult(ServerWebExchange exchange, HandlerResult result) {
        Object body = result.getReturnValue();

        if (body instanceof Mono<?> mono) {
            return mono.flatMap(value -> writeResponse(exchange, wrap(value)));
        } else if (body instanceof Flux<?> flux) {
            return flux.collectList()
                .flatMap(list -> writeResponse(exchange, wrap(list)));
        }

        return writeResponse(exchange, wrap(body));
    }

    private ApiResponse<?> wrap(Object data) {
        return ApiResponse.builder()
            .success(true)
            .data(data)
            .timestamp(Instant.now())
            .build();
    }

    private Mono<Void> writeResponse(ServerWebExchange exchange, Object body) {
        ServerHttpResponse response = exchange.getResponse();
        response.getHeaders().setContentType(MediaType.APPLICATION_JSON);

        return response.writeWith(
            Mono.fromCallable(() -> {
                byte[] bytes = objectMapper.writeValueAsBytes(body);
                return response.bufferFactory().wrap(bytes);
            })
        );
    }
}
```

## Error Handling Strategies

### Comprehensive Error Handler

```java
@Component
@Order(-2)
@RequiredArgsConstructor
@Slf4j
public class GlobalErrorWebExceptionHandler extends AbstractErrorWebExceptionHandler {

    private final ObjectMapper objectMapper;

    public GlobalErrorWebExceptionHandler(
            ErrorAttributes errorAttributes,
            WebProperties.Resources resources,
            ApplicationContext applicationContext,
            ObjectMapper objectMapper) {
        super(errorAttributes, resources, applicationContext);
        this.objectMapper = objectMapper;
        setMessageReaders(List.of());
        setMessageWriters(List.of());
    }

    @Override
    protected RouterFunction<ServerResponse> getRoutingFunction(ErrorAttributes errorAttributes) {
        return RouterFunctions.route(RequestPredicates.all(), this::renderErrorResponse);
    }

    private Mono<ServerResponse> renderErrorResponse(ServerRequest request) {
        Throwable error = getError(request);
        ErrorInfo errorInfo = mapToErrorInfo(error, request);

        logError(error, errorInfo, request);

        return ServerResponse
            .status(errorInfo.getStatus())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(ErrorResponse.builder()
                .code(errorInfo.getCode())
                .message(errorInfo.getMessage())
                .details(errorInfo.getDetails())
                .path(request.path())
                .timestamp(Instant.now())
                .traceId(getTraceId(request))
                .build());
    }

    private ErrorInfo mapToErrorInfo(Throwable error, ServerRequest request) {
        return switch (error) {
            case ValidationException e -> new ErrorInfo(
                HttpStatus.BAD_REQUEST,
                "VALIDATION_ERROR",
                "Validation failed",
                e.getErrors()
            );
            case NotFoundException e -> new ErrorInfo(
                HttpStatus.NOT_FOUND,
                "NOT_FOUND",
                e.getMessage(),
                null
            );
            case UnauthorizedException e -> new ErrorInfo(
                HttpStatus.UNAUTHORIZED,
                "UNAUTHORIZED",
                "Authentication required",
                null
            );
            case ForbiddenException e -> new ErrorInfo(
                HttpStatus.FORBIDDEN,
                "FORBIDDEN",
                "Access denied",
                null
            );
            case ConflictException e -> new ErrorInfo(
                HttpStatus.CONFLICT,
                "CONFLICT",
                e.getMessage(),
                null
            );
            case RateLimitException e -> new ErrorInfo(
                HttpStatus.TOO_MANY_REQUESTS,
                "RATE_LIMITED",
                "Too many requests",
                Map.of("retryAfter", e.getRetryAfterSeconds())
            );
            case WebClientResponseException e -> new ErrorInfo(
                HttpStatus.BAD_GATEWAY,
                "UPSTREAM_ERROR",
                "External service error",
                null
            );
            default -> new ErrorInfo(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "INTERNAL_ERROR",
                "An unexpected error occurred",
                null
            );
        };
    }

    private void logError(Throwable error, ErrorInfo errorInfo, ServerRequest request) {
        if (errorInfo.getStatus().is5xxServerError()) {
            log.error("Server error on {} {}: {}",
                request.method(), request.path(), error.getMessage(), error);
        } else {
            log.warn("Client error on {} {}: {}",
                request.method(), request.path(), error.getMessage());
        }
    }

    private String getTraceId(ServerRequest request) {
        return request.headers().firstHeader("X-Trace-Id");
    }
}
```

## Filter Patterns

### Authentication Filter

```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
@RequiredArgsConstructor
public class JwtAuthenticationWebFilter implements WebFilter {

    private final JwtTokenProvider tokenProvider;
    private final ReactiveUserDetailsService userDetailsService;

    private static final List<String> PUBLIC_PATHS = List.of(
        "/api/auth/login",
        "/api/auth/register",
        "/api/public/**",
        "/actuator/health"
    );

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();
        String path = request.getPath().value();

        if (isPublicPath(path)) {
            return chain.filter(exchange);
        }

        return extractToken(request)
            .flatMap(token -> tokenProvider.validateToken(token)
                .filter(valid -> valid)
                .flatMap(valid -> tokenProvider.getUsername(token))
                .flatMap(userDetailsService::findByUsername)
                .map(this::createAuthentication))
            .flatMap(auth -> chain.filter(exchange)
                .contextWrite(ReactiveSecurityContextHolder.withAuthentication(auth)))
            .switchIfEmpty(chain.filter(exchange));
    }

    private boolean isPublicPath(String path) {
        return PUBLIC_PATHS.stream()
            .anyMatch(pattern -> new AntPathMatcher().match(pattern, path));
    }

    private Mono<String> extractToken(ServerHttpRequest request) {
        String bearerToken = request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        if (bearerToken != null && bearerToken.startsWith("Bearer ")) {
            return Mono.just(bearerToken.substring(7));
        }
        return Mono.empty();
    }

    private Authentication createAuthentication(UserDetails userDetails) {
        return new UsernamePasswordAuthenticationToken(
            userDetails,
            null,
            userDetails.getAuthorities()
        );
    }
}
```

### Rate Limiting Filter

```java
@Component
@RequiredArgsConstructor
public class RateLimitingWebFilter implements WebFilter {

    private final RateLimiterService rateLimiterService;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String clientId = getClientId(exchange);
        String endpoint = exchange.getRequest().getPath().value();

        return rateLimiterService.isAllowed(clientId, endpoint)
            .flatMap(allowed -> {
                if (allowed) {
                    return chain.filter(exchange);
                } else {
                    return rateLimiterService.getRetryAfter(clientId, endpoint)
                        .flatMap(retryAfter -> {
                            ServerHttpResponse response = exchange.getResponse();
                            response.setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                            response.getHeaders().add("Retry-After",
                                String.valueOf(retryAfter));
                            return response.setComplete();
                        });
                }
            });
    }

    private String getClientId(ServerWebExchange exchange) {
        // Try to get from authenticated user
        return exchange.getPrincipal()
            .map(Principal::getName)
            .defaultIfEmpty(getClientIp(exchange))
            .block();
    }

    private String getClientIp(ServerWebExchange exchange) {
        String xForwardedFor = exchange.getRequest().getHeaders()
            .getFirst("X-Forwarded-For");
        if (xForwardedFor != null) {
            return xForwardedFor.split(",")[0].trim();
        }
        InetSocketAddress remoteAddress = exchange.getRequest().getRemoteAddress();
        return remoteAddress != null ? remoteAddress.getHostString() : "unknown";
    }
}
```

### Request/Response Logging Filter

```java
@Component
@Slf4j
public class RequestLoggingWebFilter implements WebFilter {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        long startTime = System.currentTimeMillis();
        ServerHttpRequest request = exchange.getRequest();

        String requestId = UUID.randomUUID().toString();

        log.info("Request [{}] {} {} from {}",
            requestId,
            request.getMethod(),
            request.getPath(),
            getClientIp(request));

        ServerWebExchange mutatedExchange = exchange.mutate()
            .request(request.mutate()
                .header("X-Request-Id", requestId)
                .build())
            .build();

        return chain.filter(mutatedExchange)
            .doFinally(signalType -> {
                long duration = System.currentTimeMillis() - startTime;
                HttpStatusCode status = exchange.getResponse().getStatusCode();

                log.info("Response [{}] {} {} - {} in {}ms",
                    requestId,
                    request.getMethod(),
                    request.getPath(),
                    status != null ? status.value() : "unknown",
                    duration);
            });
    }
}
```

### Caching Filter

```java
@Component
@RequiredArgsConstructor
public class CachingWebFilter implements WebFilter {

    private final ReactiveRedisTemplate<String, CachedResponse> cacheTemplate;
    private final ObjectMapper objectMapper;

    private static final Duration DEFAULT_TTL = Duration.ofMinutes(5);

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();

        if (!HttpMethod.GET.equals(request.getMethod())) {
            return chain.filter(exchange);
        }

        String cacheKey = buildCacheKey(request);

        return cacheTemplate.opsForValue().get(cacheKey)
            .flatMap(cached -> writeCachedResponse(exchange, cached))
            .switchIfEmpty(Mono.defer(() ->
                cacheAndProceed(exchange, chain, cacheKey)));
    }

    private Mono<Void> writeCachedResponse(
            ServerWebExchange exchange,
            CachedResponse cached) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatusCode.valueOf(cached.getStatusCode()));
        response.getHeaders().putAll(cached.getHeaders());
        response.getHeaders().add("X-Cache", "HIT");

        return response.writeWith(
            Mono.just(response.bufferFactory().wrap(cached.getBody()))
        );
    }

    private Mono<Void> cacheAndProceed(
            ServerWebExchange exchange,
            WebFilterChain chain,
            String cacheKey) {

        ServerHttpResponseDecorator decoratedResponse =
            new ServerHttpResponseDecorator(exchange.getResponse()) {

            @Override
            public Mono<Void> writeWith(Publisher<? extends DataBuffer> body) {
                return DataBufferUtils.join(body)
                    .flatMap(buffer -> {
                        byte[] bytes = new byte[buffer.readableByteCount()];
                        buffer.read(bytes);
                        DataBufferUtils.release(buffer);

                        CachedResponse cached = new CachedResponse(
                            getStatusCode().value(),
                            getHeaders(),
                            bytes
                        );

                        return cacheTemplate.opsForValue()
                            .set(cacheKey, cached, DEFAULT_TTL)
                            .then(getDelegate().writeWith(
                                Mono.just(bufferFactory().wrap(bytes))));
                    });
            }
        };

        decoratedResponse.getHeaders().add("X-Cache", "MISS");

        return chain.filter(exchange.mutate()
            .response(decoratedResponse)
            .build());
    }

    private String buildCacheKey(ServerHttpRequest request) {
        return "cache:" + request.getPath().value() +
            "?" + request.getQueryParams().toString();
    }
}
```
