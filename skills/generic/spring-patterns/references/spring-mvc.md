# Spring MVC Patterns Reference

Full patterns for Java 17+ / Spring Boot 3.x servlet stack.

## Table of Contents
- [REST Controller](#rest-controller)
- [Response Envelope](#response-envelope)
- [Global Exception Handler](#global-exception-handler)
- [Request Validation](#request-validation)
- [Filters](#filters)
- [Interceptors](#interceptors)
- [Security Configuration](#security-configuration)
- [Pagination](#pagination)
- [Testing with MockMvc](#testing-with-mockmvc)

---

## REST Controller

```java
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
@Slf4j
@Tag(name = "Orders", description = "Order management API")
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

---

## Response Envelope

```java
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

- Domain exceptions -> 404/409/422
- `MethodArgumentNotValidException` -> 400 with field errors
- `ConstraintViolationException` -> 400 with field errors
- `AccessDeniedException` -> 403
- Catch-all -> 500 (log full stack, return generic message -- never expose internals)

Use RFC 7807 `ProblemDetail` for standardized error responses.

---

## Request Validation

```java
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

// Custom validator
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

## Filters

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
            log.info("HTTP {} {} -> {} ({}ms)",
                request.getMethod(), request.getRequestURI(),
                response.getStatus(), duration);
            MDC.clear();
        }
    }
}
```

---

## Interceptors

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
            .csrf(AbstractHttpConfigurer::disable)
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

## Pagination

### Offset-Based (Page)

```java
@GetMapping
public Page<OrderSummary> list(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") @Max(100) int size) {
    return orderQuery.list(PageRequest.of(page, Math.min(size, 100)));
}
// Response: { "content": [...], "totalElements": 150, "totalPages": 8, "number": 0 }
```

### Cursor-Based (Keyset)

```java
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

Use `Page<T>` when UI needs total count. Use `Slice<T>` / cursor for infinite scroll (avoids `COUNT(*)` query).

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
