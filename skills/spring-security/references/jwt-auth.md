# JWT Authentication Reference

JWT filter, token generation, and token validation for MVC and WebFlux.

---

## JWT Authentication Filter (MVC)

```java
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider tokenProvider;
    private final UserDetailsService userDetailsService;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
            HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        String token = extractToken(request);
        if (token != null && tokenProvider.validateToken(token)) {
            String username = tokenProvider.getUsername(token);
            UserDetails userDetails = userDetailsService.loadUserByUsername(username);

            var authentication = new UsernamePasswordAuthenticationToken(
                userDetails, null, userDetails.getAuthorities());
            authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));

            SecurityContextHolder.getContext().setAuthentication(authentication);
        }

        filterChain.doFilter(request, response);
    }

    private String extractToken(HttpServletRequest request) {
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header != null && header.startsWith("Bearer ")) {
            return header.substring(7);
        }
        return null;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getServletPath();
        return path.startsWith("/api/v1/auth/") || path.startsWith("/actuator/health");
    }
}
```

---

## SecurityFilterChain (MVC)

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtFilter;
    private final AuthenticationEntryPoint authEntryPoint;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable) // Disable for stateless API
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .exceptionHandling(ex ->
                ex.authenticationEntryPoint(authEntryPoint))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/auth/**").permitAll()
                .requestMatchers("/actuator/health").permitAll()
                .requestMatchers("/api/v1/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated()
            )
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
            .build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12); // Cost factor 12
    }
}
```

---

## SecurityWebFilterChain (WebFlux)

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtTokenProvider tokenProvider;

    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(csrf -> csrf.disable())  // API-only: no forms/sessions
            .cors(cors -> cors.configurationSource(corsConfigSource()))
            .headers(headers -> headers
                .frameOptions(ServerHttpSecurity.HeaderSpec.FrameOptionsSpec::deny)
                .contentTypeOptions(Customizer.withDefaults())
                .hsts(hsts -> hsts.maxAge(Duration.ofDays(365)).includeSubdomains(true)))
            .authorizeExchange(auth -> auth
                .pathMatchers("/api/public/**").permitAll()
                .pathMatchers("/actuator/health", "/actuator/info").permitAll()
                .pathMatchers("/api/admin/**").hasRole("ADMIN")
                .pathMatchers(HttpMethod.GET, "/api/v1/**").hasAnyRole("USER", "ADMIN")
                .anyExchange().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt ->
                jwt.jwtAuthenticationConverter(jwtConverter())))
            .build();
    }

    @Bean
    public ReactiveJwtAuthenticationConverter jwtConverter() {
        var converter = new ReactiveJwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            @SuppressWarnings("unchecked")
            List<String> roles = (List<String>) jwt.getClaims().getOrDefault("roles", List.of());
            return Flux.fromIterable(roles)
                .map(role -> (GrantedAuthority) new SimpleGrantedAuthority("ROLE_" + role));
        });
        return converter;
    }
}
```

---

## JWT Token Provider

```java
@Component
public class JwtTokenProvider {

    private final SecretKey secretKey;
    private final Duration expiration;

    public JwtTokenProvider(SecurityProperties props) {
        this.secretKey = Keys.hmacShaKeyFor(props.jwtSecret().getBytes(StandardCharsets.UTF_8));
        this.expiration = props.jwtExpiration();
    }

    public String generate(String userId, List<String> roles) {
        Instant now = Instant.now();
        return Jwts.builder()
            .subject(userId)
            .claim("roles", roles)
            .issuedAt(Date.from(now))
            .expiration(Date.from(now.plus(expiration)))
            .signWith(secretKey)
            .compact();
    }

    public JwtClaims validate(String token) {
        try {
            var claims = Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();

            if (claims.getExpiration().before(new Date())) {
                throw new JwtValidationException("Token expired");
            }

            @SuppressWarnings("unchecked")
            List<String> roles = (List<String>) claims.get("roles");
            return new JwtClaims(claims.getSubject(), roles);
        } catch (JwtException e) {
            throw new JwtValidationException("Invalid token");
        }
    }
}
```

---

## Method Security

### MVC (Blocking)

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    @PreAuthorize("@orderSecurity.isOwner(#id, authentication) or hasRole('ADMIN')")
    public OrderDto findById(Long id) { ... }

    @PreAuthorize("isAuthenticated()")
    public OrderDto createOrder(CreateOrderCommand command) { ... }

    @PostFilter("filterObject.ownerId == authentication.name or hasRole('ADMIN')")
    public List<OrderDto> findAll() { ... }
}

@Component("orderSecurity")
@RequiredArgsConstructor
public class OrderSecurityEvaluator {
    private final OrderRepository orderRepository;

    public boolean isOwner(Long orderId, Authentication auth) {
        return orderRepository.findById(orderId)
            .map(order -> order.getCustomerId().equals(auth.getName()))
            .orElse(false);
    }
}
```

### WebFlux (Reactive)

```java
@Service @RequiredArgsConstructor
@Slf4j
public class OrderService {

    @PreAuthorize("hasRole('ADMIN') or #userId == authentication.name")
    public Flux<Order> findByUser(String userId) { ... }

    @PreAuthorize("hasRole('ADMIN')")
    public Mono<Void> deleteOrder(String orderId) { ... }

    @PreAuthorize("@orderPermissions.canModify(authentication, #orderId)")
    public Mono<Order> updateOrder(String orderId, UpdateOrderRequest request) { ... }
}

@Component
public class OrderPermissions {
    public Mono<Boolean> canModify(Authentication auth, String orderId) {
        if (auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"))) {
            return Mono.just(true);
        }
        return orderRepository.findById(orderId)
            .map(order -> order.getCustomerId().equals(auth.getName()))
            .defaultIfEmpty(false);
    }
}
```
