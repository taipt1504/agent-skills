---
name: spring-mvc-patterns
description: Servlet Spring stack patterns — @RestController, MockMvc, HandlerInterceptor, OncePerRequestFilter, JPA, Pageable, RestTemplate/RestClient. Project must use Spring MVC (blocking, 1-thread-per-request). Mutually exclusive with spring-webflux-patterns.
triggers:
  natural: ["servlet endpoint", "rest controller", "mockmvc test", "rest template"]
  code: ["@RestController", "MockMvc", "HttpServletRequest", "RestTemplate", "RestClient", "OncePerRequestFilter"]
applicability:
  always: false
  triggers:
    files_match: ["**/*Controller.java", "**/*Filter.java", "**/*Interceptor.java", "**/application*.yml"]
    code_patterns: ["HttpServletRequest", "HttpServletResponse", "RestTemplate", "RestClient", "OncePerRequestFilter", "HandlerInterceptor", "JpaRepository", "MockMvc"]
    task_keywords: ["mvc", "servlet", "blocking", "JPA", "RestTemplate", "MockMvc"]
    related_rules:
      - rules/java/api-design.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 90%+: project uses Spring MVC (verified: spring-boot-starter-web on classpath, no spring-boot-starter-webflux)
  HIGH 80%+: task adds REST endpoint OR uses RestTemplate/RestClient
  MEDIUM 40-79%: task touches MVC infrastructure (filter, interceptor, MockMvc test)
  LOW 1-39%: task tangentially related (e.g., DTO that crosses servlet boundary)
  ZERO: project uses WebFlux (reactive stack); verify in application.yml
---

# Spring MVC Patterns — Servlet Stack

## Stack constraint

MVC is blocking, 1 thread per request. NEVER mix with WebFlux. Verify:
- `spring-boot-starter-web` on classpath (no `spring-boot-starter-webflux`)
- All I/O OK to block: JDBC/JPA, Jedis, spring-kafka (blocking consumer fine)
- Throughput: moderate (<1k concurrent) — saturates at thread pool

## Controller pattern

```java
@RestController
@RequestMapping("/api/v1/orders")
@RequiredArgsConstructor
@Validated
public class OrderController {
    private final CreateOrderUseCase createOrderUseCase;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public OrderResponse createOrder(@Valid @RequestBody CreateOrderRequest request) {
        return createOrderUseCase.execute(request);
    }

    @GetMapping
    public Page<OrderDto> list(@PageableDefault(size = 20) Pageable pageable) {
        return orderQueryService.findAll(pageable);
    }
}
```

**Rules:** `@RequiredArgsConstructor`, `@Valid` on request bodies, return DTOs (never entities), `Pageable` with `@Max(100)` size cap.

## Filter — `OncePerRequestFilter`

```java
@Component
public class TracingFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse resp, FilterChain chain)
        throws ServletException, IOException {
        String requestId = Optional.ofNullable(req.getHeader("X-Request-Id"))
            .orElse(UUID.randomUUID().toString());
        MDC.put("requestId", requestId);
        try {
            chain.doFilter(req, resp);
        } finally {
            MDC.clear();
        }
    }
}
```

MDC works in MVC (ThreadLocal) — different from WebFlux Reactor Context.

## HandlerInterceptor (rate limiting, auth checks)

```java
@Component
@RequiredArgsConstructor
public class RateLimitInterceptor implements HandlerInterceptor {
    private final RateLimiter rateLimiter;

    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse resp, Object handler) {
        if (!rateLimiter.tryAcquire(req.getRemoteAddr())) {
            resp.setStatus(429);
            return false;
        }
        return true;
    }
}
```

Register via `WebMvcConfigurer.addInterceptors()`.


## JPA transactions

```java
@Service
@RequiredArgsConstructor
public class OrderService {
    private final OrderRepository repo;

    @Transactional
    public Order placeOrder(Order order) {
        Order saved = repo.save(order);
        eventPublisher.publish(saved);
        return saved;
    }

    @Transactional(readOnly = true)
    public Page<Order> findAll(Pageable pageable) {
        return repo.findAll(pageable);
    }
}
```

`@Transactional(readOnly = true)` on query methods — JPA optimization. Always set `spring.jpa.open-in-view: false`.

## Security filter

Servlet security via `SecurityFilterChain` (NOT `SecurityWebFilterChain`):

```java
@Bean
public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
    return http
        .authorizeHttpRequests(auth -> auth
            .requestMatchers("/actuator/health").permitAll()
            .anyRequest().authenticated())
        .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()))
        .build();
}
```

Method security: `@EnableMethodSecurity` (not `@EnableReactiveMethodSecurity`).


## HTTP client — RestClient (Spring 6.1+) or RestTemplate

```java
@Configuration
public class HttpClientConfig {
    @Bean
    public RestClient userServiceClient(@Value("${user-service.url}") String baseUrl) {
        return RestClient.builder()
            .baseUrl(baseUrl)
            .requestFactory(new SimpleClientHttpRequestFactory() {{
                setConnectTimeout(2000);
                setReadTimeout(5000);
            }})
            .build();
    }
}
```

Prefer `RestClient` over `RestTemplate` in Spring 6.1+. ALWAYS set timeouts.

## Testing — MockMvc

```java
@WebMvcTest(OrderController.class)
class OrderControllerTest {
    @Autowired MockMvc mockMvc;
    @MockBean CreateOrderUseCase createOrderUseCase;

    @Test
    void shouldCreateOrderWhenValidRequest() throws Exception {
        mockMvc.perform(post("/api/v1/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"productId\":\"p1\",\"quantity\":2}"))
            .andExpect(status().isCreated());
    }
}
```

`@WebMvcTest` slices context to controller layer. Mock use case.

## Anti-patterns

| Anti-pattern | Fix |
|---|---|
| `@Autowired` field injection | `@RequiredArgsConstructor` |
| Entities in API responses | Map to DTOs |
| `spring.jpa.open-in-view: true` | Set to `false` |
| `RestTemplate` without timeouts | Always set connect + read timeouts |
| Missing `@Transactional(readOnly=true)` on queries | Add it — JPA performance |
| Returning `Page<Entity>` | Map to `Page<EntityDto>` |
| Unbounded `Pageable` size | `@Max(100)` on size parameter |
| `RestTemplate` in Spring 6.1+ | Prefer `RestClient` |

## Verification checklist

- [ ] `@RequiredArgsConstructor` (no `@Autowired`)
- [ ] `@Valid` on request bodies
- [ ] DTOs returned (never entities)
- [ ] `@Transactional(readOnly = true)` on queries
- [ ] `spring.jpa.open-in-view: false`
- [ ] Pagination capped (`@Max(100)`)
- [ ] HTTP client timeouts configured
- [ ] MockMvc tests cover controllers
- [ ] Graceful shutdown + actuator configured

## References

- **[references/spring-mvc.md](references/spring-mvc.md)** — Full controller patterns, MockMvc, filters, interceptors, pagination
- **[references/springboot-production.md](references/springboot-production.md)** — Caching, async, rate limiting, Jackson, HikariCP, graceful shutdown
- **[references/springboot-3x-features.md](references/springboot-3x-features.md)** — Virtual threads (3.2+), `@HttpExchange`, Observation API

## Related

- `skills/spring-security` — `SecurityFilterChain`
- `skills/database-patterns` — JPA repository patterns
- `skills/api-design` — REST conventions, RFC 7807
- `skills/testing-workflow` — MockMvc, @WebMvcTest
