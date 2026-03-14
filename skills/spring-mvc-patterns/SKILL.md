---
name: spring-mvc-patterns
description: Spring MVC (servlet-based) patterns for Java Spring Boot applications. Use when building REST APIs with Spring MVC, implementing controllers, exception handlers, filters, interceptors, or reviewing servlet-based Spring code. Covers controller design, request validation, error handling, security configuration, pagination, and testing with MockMvc.
---

# Spring MVC Patterns

Production-ready Spring MVC patterns for Java 17+ / Spring Boot 3.x (servlet stack).

## Quick Reference

| Category | Jump To |
|----------|---------|
| Controller Design | [Controller Patterns](#controller-patterns) |
| Exception Handling | [Global Exception Handler](#global-exception-handler) |
| Validation | [Request Validation](#request-validation) |
| Filters & Interceptors | [Filters & Interceptors](#filters--interceptors) |
| Security | [Security Config](#security-configuration) |
| Pagination | [Pagination Patterns](#pagination-patterns) |
| Testing | [Testing with MockMvc](#testing-with-mockmvc) |

---

## Controller Patterns

### REST Controller Best Practices

```java
// ✅ Well-structured Spring MVC controller
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
@Slf4j
@Tag(name = "Orders", description = "Order management API")  // OpenAPI
public class OrderController {

    private final OrderService orderService;
    private final OrderMapper orderMapper;

    @GetMapping
    @Operation(summary = "List orders with pagination")
    public ResponseEntity<Page<OrderResponse>> listOrders(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) OrderStatus status,
            @AuthenticationPrincipal UserPrincipal principal) {

        Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
        Page<Order> orders = orderService.findByUser(principal.getUserId(), status, pageable);
        return ResponseEntity.ok(orders.map(orderMapper::toResponse));
    }

    @GetMapping("/{id}")
    public ResponseEntity<OrderResponse> getOrder(
            @PathVariable Long id,
            @AuthenticationPrincipal UserPrincipal principal) {

        return orderService.findById(id, principal.getUserId())
            .map(orderMapper::toResponse)
            .map(ResponseEntity::ok)
            .orElseThrow(() -> new ResourceNotFoundException("Order", id));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public OrderResponse createOrder(
            @Valid @RequestBody CreateOrderRequest request,
            @AuthenticationPrincipal UserPrincipal principal) {

        Order order = orderService.create(principal.getUserId(), request);
        return orderMapper.toResponse(order);
    }

    @PatchMapping("/{id}/status")
    public ResponseEntity<OrderResponse> updateStatus(
            @PathVariable Long id,
            @Valid @RequestBody UpdateOrderStatusRequest request,
            @AuthenticationPrincipal UserPrincipal principal) {

        Order updated = orderService.updateStatus(id, principal.getUserId(), request.status());
        return ResponseEntity.ok(orderMapper.toResponse(updated));
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteOrder(@PathVariable Long id,
                             @AuthenticationPrincipal UserPrincipal principal) {
        orderService.delete(id, principal.getUserId());
    }
}
```

### Response Envelope Pattern

```java
// ✅ Consistent API response wrapper
public record ApiResponse<T>(
    boolean success,
    T data,
    String message,
    @JsonInclude(JsonInclude.Include.NON_NULL) List<FieldError> errors
) {
    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(true, data, null, null);
    }

    public static <T> ApiResponse<T> error(String message) {
        return new ApiResponse<>(false, null, message, null);
    }

    public static <T> ApiResponse<T> validationError(List<FieldError> errors) {
        return new ApiResponse<>(false, null, "Validation failed", errors);
    }
}
```

---

## Global Exception Handler

Use `@RestControllerAdvice` with centralized exception handling. Must cover:

- Domain exceptions → 404/409/422
- `MethodArgumentNotValidException` → 400 with field errors
- `ConstraintViolationException` → 400 with field errors
- `AccessDeniedException` → 403
- Catch-all → 500 (log full stack, return generic message — never expose internals)

> See `api-design` skill for full GlobalExceptionHandler implementation with RFC 7807.

---

## Request Validation

```java
// ✅ Request DTO with Bean Validation
public record CreateOrderRequest(
    @NotNull(message = "User ID is required")
    Long userId,

    @NotEmpty(message = "At least one item is required")
    @Size(max = 100, message = "Maximum 100 items per order")
    List<@Valid OrderItemRequest> items,

    @NotBlank(message = "Delivery address is required")
    @Size(max = 500)
    String deliveryAddress,

    @Future(message = "Requested delivery date must be in the future")
    LocalDate requestedDeliveryDate
) {}

public record OrderItemRequest(
    @NotNull Long productId,
    @Min(value = 1, message = "Quantity must be at least 1")
    @Max(value = 999, message = "Maximum quantity is 999")
    Integer quantity
) {}

// ✅ Custom validator
@Target({ElementType.FIELD})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = ValidOrderStatusValidator.class)
public @interface ValidOrderStatus {
    String message() default "Invalid order status";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

@Component
public class ValidOrderStatusValidator
        implements ConstraintValidator<ValidOrderStatus, String> {

    private final Set<String> validStatuses = Set.of("PENDING", "CONFIRMED", "CANCELLED");

    @Override
    public boolean isValid(String value, ConstraintValidatorContext ctx) {
        return value != null && validStatuses.contains(value.toUpperCase());
    }
}
```

---

## Filters & Interceptors

### Request Logging Filter

```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
@Slf4j
public class RequestLoggingFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                     HttpServletResponse response,
                                     FilterChain chain) throws IOException, ServletException {
        String requestId = UUID.randomUUID().toString();
        MDC.put("requestId", requestId);
        MDC.put("method", request.getMethod());
        MDC.put("uri", request.getRequestURI());

        long startTime = System.currentTimeMillis();
        try {
            chain.doFilter(request, response);
        } finally {
            long duration = System.currentTimeMillis() - startTime;
            log.info("HTTP {} {} → {} ({}ms)",
                request.getMethod(), request.getRequestURI(),
                response.getStatus(), duration);
            MDC.clear();
        }
    }
}
```

### Rate Limiting Interceptor (Redis-based)

```java
@Component
@RequiredArgsConstructor
public class RateLimitInterceptor implements HandlerInterceptor {

    private final RedisTemplate<String, Integer> redisTemplate;
    private static final int MAX_REQUESTS_PER_MINUTE = 60;

    @Override
    public boolean preHandle(HttpServletRequest request,
                              HttpServletResponse response,
                              Object handler) throws Exception {
        String clientId = extractClientId(request);
        String key = "rate-limit:" + clientId + ":" + getCurrentMinuteBucket();

        Long count = redisTemplate.opsForValue().increment(key);
        if (count == 1) {
            redisTemplate.expire(key, Duration.ofMinutes(2));
        }

        if (count > MAX_REQUESTS_PER_MINUTE) {
            response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
            response.setHeader("X-RateLimit-Limit", String.valueOf(MAX_REQUESTS_PER_MINUTE));
            response.setHeader("X-RateLimit-Remaining", "0");
            response.setHeader("Retry-After", "60");
            return false;
        }

        response.setHeader("X-RateLimit-Remaining",
            String.valueOf(MAX_REQUESTS_PER_MINUTE - count));
        return true;
    }
}
```

---

## Security Configuration

```java
@Configuration
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtFilter;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable)      // Stateless API — no CSRF needed
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/auth/**").permitAll()
                .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/v1/public/**").permitAll()
                .requestMatchers("/api/v1/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthConverter())))
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED))
                .accessDeniedHandler(new CustomAccessDeniedHandler()))
            .build();
    }
}
```

---

## Pagination Patterns

```java
// ✅ Pagination with cursor (keyset) — production-grade for large datasets
@GetMapping("/scroll")
public ResponseEntity<CursorPage<OrderResponse>> scrollOrders(
        @RequestParam(required = false) String cursor,
        @RequestParam(defaultValue = "20") int size,
        @AuthenticationPrincipal UserPrincipal principal) {

    CursorPage<Order> page = orderService.findByCursor(
        principal.getUserId(), cursor, size);

    return ResponseEntity.ok()
        .header("X-Next-Cursor", page.nextCursor())
        .body(page.map(orderMapper::toResponse));
}

public record CursorPage<T>(List<T> items, String nextCursor, boolean hasMore) {
    public <R> CursorPage<R> map(Function<T, R> mapper) {
        return new CursorPage<>(items.stream().map(mapper).toList(), nextCursor, hasMore);
    }
}
```

---

## Testing with MockMvc

```java
@WebMvcTest(OrderController.class)
@Import(SecurityConfig.class)
class OrderControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private OrderService orderService;

    @MockBean
    private OrderMapper orderMapper;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    @WithMockUser(roles = "USER")
    void shouldReturnOrdersPageForAuthenticatedUser() throws Exception {
        var orders = List.of(new OrderResponse(1L, "PENDING", BigDecimal.TEN));
        var page = new PageImpl<>(orders);
        when(orderService.findByUser(any(), any(), any())).thenReturn(page);
        when(orderMapper.toResponse(any())).thenReturn(orders.getFirst());

        mockMvc.perform(get("/api/v1/orders")
                .param("page", "0")
                .param("size", "20")
                .contentType(MediaType.APPLICATION_JSON))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.content", hasSize(1)))
            .andExpect(jsonPath("$.content[0].status").value("PENDING"));
    }

    @Test
    void shouldReturn401WhenUnauthenticated() throws Exception {
        mockMvc.perform(get("/api/v1/orders"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser
    void shouldReturn400ForInvalidCreateRequest() throws Exception {
        var invalidRequest = new CreateOrderRequest(null, List.of(), "", null);

        mockMvc.perform(post("/api/v1/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(invalidRequest)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.success").value(false))
            .andExpect(jsonPath("$.errors").isArray());
    }
}
```

## When to Use Spring MVC vs Spring WebFlux

| Criteria | Spring MVC | Spring WebFlux |
|----------|-----------|----------------|
| I/O model | Blocking (1 thread/request) | Non-blocking (event loop) |
| Database | JPA/Hibernate (JDBC) | R2DBC |
| Throughput needs | Moderate (< 1K req/s) | High (> 1K req/s concurrent) |
| Team familiarity | Traditional Java | Reactive programming |
| Third-party libs | Most support MVC | Reactive libs required |
| Testing | MockMvc (simpler) | WebTestClient (reactive) |
