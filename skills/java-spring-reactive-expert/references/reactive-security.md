# Reactive Security Reference

## Table of Contents
- [ReactiveSecurityContextHolder](#reactivesecuritycontextholder)
- [JWT Authentication Reactive](#jwt-authentication-reactive)
- [OAuth2 Reactive Client](#oauth2-reactive-client)
- [Method-Level Security](#method-level-security)
- [CORS Configuration](#cors-configuration)
- [Security Filters](#security-filters)
- [Authentication Patterns](#authentication-patterns)
- [Authorization Patterns](#authorization-patterns)

## ReactiveSecurityContextHolder

### Basic Usage

```java
import org.springframework.security.core.context.ReactiveSecurityContextHolder;
import org.springframework.security.core.context.SecurityContext;

@Service
@RequiredArgsConstructor
public class SecureService {

    public Mono<String> getCurrentUsername() {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(Authentication::getName);
    }

    public Mono<User> getCurrentUser() {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(auth -> (User) auth.getPrincipal());
    }

    public Mono<Boolean> hasRole(String role) {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(auth -> auth.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .anyMatch(a -> a.equals("ROLE_" + role)));
    }

    public Mono<Set<String>> getCurrentUserRoles() {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(auth -> auth.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .collect(Collectors.toSet()));
    }
}
```

### Context Propagation Pattern

```java
@Service
public class ContextAwareService {

    // Context is automatically propagated in reactive chain
    public Mono<Result> processSecurely(Request request) {
        return ReactiveSecurityContextHolder.getContext()
            .flatMap(securityContext -> {
                Authentication auth = securityContext.getAuthentication();
                return processWithAuth(request, auth);
            });
    }

    // Manual context propagation when needed
    public Mono<Result> processWithManualContext(Request request) {
        return ReactiveSecurityContextHolder.getContext()
            .flatMap(ctx -> someExternalCall(request)
                .contextWrite(ReactiveSecurityContextHolder.withSecurityContext(
                    Mono.just(ctx))));
    }

    // Context in parallel operations
    public Mono<AggregatedResult> parallelSecureOperations(String userId) {
        return ReactiveSecurityContextHolder.getContext()
            .flatMap(ctx -> {
                Mono<Data1> data1 = fetchData1(userId)
                    .contextWrite(ReactiveSecurityContextHolder.withSecurityContext(
                        Mono.just(ctx)));
                Mono<Data2> data2 = fetchData2(userId)
                    .contextWrite(ReactiveSecurityContextHolder.withSecurityContext(
                        Mono.just(ctx)));

                return Mono.zip(data1, data2)
                    .map(tuple -> new AggregatedResult(tuple.getT1(), tuple.getT2()));
            });
    }
}
```

### Custom Security Context Repository

```java
@Component
public class JwtSecurityContextRepository implements ServerSecurityContextRepository {

    private final JwtTokenProvider tokenProvider;
    private final ReactiveUserDetailsService userDetailsService;

    @Override
    public Mono<Void> save(ServerWebExchange exchange, SecurityContext context) {
        // JWT is stateless, no save needed
        return Mono.empty();
    }

    @Override
    public Mono<SecurityContext> load(ServerWebExchange exchange) {
        return Mono.justOrEmpty(extractToken(exchange.getRequest()))
            .filter(tokenProvider::validateToken)
            .flatMap(token -> {
                String username = tokenProvider.getUsername(token);
                return userDetailsService.findByUsername(username);
            })
            .map(userDetails -> {
                Authentication auth = new UsernamePasswordAuthenticationToken(
                    userDetails,
                    null,
                    userDetails.getAuthorities()
                );
                return new SecurityContextImpl(auth);
            });
    }

    private String extractToken(ServerHttpRequest request) {
        String bearerToken = request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        if (bearerToken != null && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
    }
}
```

## JWT Authentication Reactive

### JWT Token Provider

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class JwtTokenProvider {

    private final JwtProperties jwtProperties;

    @PostConstruct
    public void init() {
        // Validate configuration
        if (jwtProperties.getSecret().length() < 32) {
            throw new IllegalStateException("JWT secret must be at least 32 characters");
        }
    }

    public String generateToken(UserDetails userDetails) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("roles", userDetails.getAuthorities().stream()
            .map(GrantedAuthority::getAuthority)
            .collect(Collectors.toList()));

        return Jwts.builder()
            .setClaims(claims)
            .setSubject(userDetails.getUsername())
            .setIssuedAt(new Date())
            .setExpiration(new Date(System.currentTimeMillis() +
                jwtProperties.getExpiration().toMillis()))
            .signWith(getSigningKey(), SignatureAlgorithm.HS512)
            .compact();
    }

    public String generateRefreshToken(UserDetails userDetails) {
        return Jwts.builder()
            .setSubject(userDetails.getUsername())
            .setIssuedAt(new Date())
            .setExpiration(new Date(System.currentTimeMillis() +
                jwtProperties.getRefreshExpiration().toMillis()))
            .signWith(getSigningKey(), SignatureAlgorithm.HS512)
            .compact();
    }

    public Mono<Boolean> validateToken(String token) {
        return Mono.fromCallable(() -> {
            try {
                Jwts.parserBuilder()
                    .setSigningKey(getSigningKey())
                    .build()
                    .parseClaimsJws(token);
                return true;
            } catch (JwtException | IllegalArgumentException e) {
                log.debug("Invalid JWT token: {}", e.getMessage());
                return false;
            }
        });
    }

    public Mono<String> getUsername(String token) {
        return Mono.fromCallable(() ->
            getClaims(token).getSubject());
    }

    @SuppressWarnings("unchecked")
    public Mono<List<String>> getRoles(String token) {
        return Mono.fromCallable(() ->
            (List<String>) getClaims(token).get("roles"));
    }

    private Claims getClaims(String token) {
        return Jwts.parserBuilder()
            .setSigningKey(getSigningKey())
            .build()
            .parseClaimsJws(token)
            .getBody();
    }

    private Key getSigningKey() {
        byte[] keyBytes = Decoders.BASE64.decode(jwtProperties.getSecret());
        return Keys.hmacShaKeyFor(keyBytes);
    }
}

@ConfigurationProperties(prefix = "app.jwt")
@Data
public class JwtProperties {
    private String secret;
    private Duration expiration = Duration.ofHours(1);
    private Duration refreshExpiration = Duration.ofDays(7);
}
```

### JWT Authentication Manager

```java
@Component
@RequiredArgsConstructor
public class JwtReactiveAuthenticationManager implements ReactiveAuthenticationManager {

    private final JwtTokenProvider tokenProvider;
    private final ReactiveUserDetailsService userDetailsService;

    @Override
    public Mono<Authentication> authenticate(Authentication authentication) {
        String token = authentication.getCredentials().toString();

        return tokenProvider.validateToken(token)
            .filter(valid -> valid)
            .switchIfEmpty(Mono.error(new BadCredentialsException("Invalid token")))
            .then(tokenProvider.getUsername(token))
            .flatMap(userDetailsService::findByUsername)
            .switchIfEmpty(Mono.error(new BadCredentialsException("User not found")))
            .map(userDetails -> new UsernamePasswordAuthenticationToken(
                userDetails,
                null,
                userDetails.getAuthorities()
            ));
    }
}
```

### JWT Authentication Filter

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class JwtAuthenticationWebFilter implements WebFilter {

    private final JwtTokenProvider tokenProvider;
    private final JwtReactiveAuthenticationManager authenticationManager;

    private static final PathPatternParser PATH_PARSER = new PathPatternParser();
    private static final List<PathPattern> PUBLIC_PATHS = List.of(
        PATH_PARSER.parse("/api/auth/**"),
        PATH_PARSER.parse("/api/public/**"),
        PATH_PARSER.parse("/actuator/health"),
        PATH_PARSER.parse("/actuator/info")
    );

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();
        PathContainer path = request.getPath().pathWithinApplication();

        // Skip authentication for public paths
        if (isPublicPath(path)) {
            return chain.filter(exchange);
        }

        return extractToken(request)
            .flatMap(token -> {
                Authentication auth = new UsernamePasswordAuthenticationToken(token, token);
                return authenticationManager.authenticate(auth);
            })
            .flatMap(authentication ->
                chain.filter(exchange)
                    .contextWrite(ReactiveSecurityContextHolder.withAuthentication(authentication)))
            .switchIfEmpty(chain.filter(exchange))
            .onErrorResume(AuthenticationException.class, e -> {
                log.debug("Authentication failed: {}", e.getMessage());
                return handleAuthenticationError(exchange, e);
            });
    }

    private boolean isPublicPath(PathContainer path) {
        return PUBLIC_PATHS.stream()
            .anyMatch(pattern -> pattern.matches(path));
    }

    private Mono<String> extractToken(ServerHttpRequest request) {
        return Mono.justOrEmpty(request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION))
            .filter(header -> header.startsWith("Bearer "))
            .map(header -> header.substring(7));
    }

    private Mono<Void> handleAuthenticationError(ServerWebExchange exchange, AuthenticationException e) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatus.UNAUTHORIZED);
        response.getHeaders().setContentType(MediaType.APPLICATION_JSON);

        String body = """
            {"error": "Unauthorized", "message": "%s"}
            """.formatted(e.getMessage());

        return response.writeWith(
            Mono.just(response.bufferFactory().wrap(body.getBytes())));
    }
}
```

### Complete Security Configuration

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtReactiveAuthenticationManager authenticationManager;
    private final JwtSecurityContextRepository securityContextRepository;
    private final JwtAuthenticationWebFilter jwtAuthenticationWebFilter;

    @Bean
    public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(ServerHttpSecurity.CsrfSpec::disable)
            .httpBasic(ServerHttpSecurity.HttpBasicSpec::disable)
            .formLogin(ServerHttpSecurity.FormLoginSpec::disable)
            .authenticationManager(authenticationManager)
            .securityContextRepository(securityContextRepository)
            .authorizeExchange(exchanges -> exchanges
                .pathMatchers("/api/auth/**").permitAll()
                .pathMatchers("/api/public/**").permitAll()
                .pathMatchers("/actuator/health", "/actuator/info").permitAll()
                .pathMatchers("/api/admin/**").hasRole("ADMIN")
                .pathMatchers("/api/users/**").hasAnyRole("USER", "ADMIN")
                .anyExchange().authenticated()
            )
            .addFilterAt(jwtAuthenticationWebFilter, SecurityWebFiltersOrder.AUTHENTICATION)
            .exceptionHandling(exceptionHandling -> exceptionHandling
                .authenticationEntryPoint(this::handleAuthenticationError)
                .accessDeniedHandler(this::handleAccessDenied)
            )
            .build();
    }

    private Mono<Void> handleAuthenticationError(
            ServerWebExchange exchange,
            AuthenticationException e) {
        return writeErrorResponse(exchange, HttpStatus.UNAUTHORIZED,
            "UNAUTHORIZED", "Authentication required");
    }

    private Mono<Void> handleAccessDenied(
            ServerWebExchange exchange,
            AccessDeniedException e) {
        return writeErrorResponse(exchange, HttpStatus.FORBIDDEN,
            "FORBIDDEN", "Access denied");
    }

    private Mono<Void> writeErrorResponse(
            ServerWebExchange exchange,
            HttpStatus status,
            String code,
            String message) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(status);
        response.getHeaders().setContentType(MediaType.APPLICATION_JSON);

        String body = """
            {"code": "%s", "message": "%s", "timestamp": "%s"}
            """.formatted(code, message, Instant.now());

        return response.writeWith(
            Mono.just(response.bufferFactory().wrap(body.getBytes())));
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }
}
```

### Authentication Controller

```java
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;
    private final JwtTokenProvider tokenProvider;

    @PostMapping("/login")
    public Mono<AuthResponse> login(@Valid @RequestBody Mono<LoginRequest> request) {
        return request.flatMap(authService::authenticate)
            .map(user -> AuthResponse.builder()
                .accessToken(tokenProvider.generateToken(user))
                .refreshToken(tokenProvider.generateRefreshToken(user))
                .expiresIn(Duration.ofHours(1).toSeconds())
                .tokenType("Bearer")
                .build());
    }

    @PostMapping("/refresh")
    public Mono<AuthResponse> refresh(@Valid @RequestBody Mono<RefreshRequest> request) {
        return request.flatMap(req ->
            tokenProvider.validateToken(req.getRefreshToken())
                .filter(valid -> valid)
                .switchIfEmpty(Mono.error(new BadCredentialsException("Invalid refresh token")))
                .then(tokenProvider.getUsername(req.getRefreshToken()))
                .flatMap(authService::findByUsername)
                .map(user -> AuthResponse.builder()
                    .accessToken(tokenProvider.generateToken(user))
                    .refreshToken(tokenProvider.generateRefreshToken(user))
                    .expiresIn(Duration.ofHours(1).toSeconds())
                    .tokenType("Bearer")
                    .build()));
    }

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserDto> register(@Valid @RequestBody Mono<RegisterRequest> request) {
        return request.flatMap(authService::register)
            .map(UserMapper::toDto);
    }

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> logout(@RequestHeader("Authorization") String authorization) {
        String token = authorization.substring(7);
        return authService.invalidateToken(token);
    }

    @GetMapping("/me")
    public Mono<UserDto> getCurrentUser() {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(auth -> (User) auth.getPrincipal())
            .map(UserMapper::toDto);
    }
}
```

## OAuth2 Reactive Client

### OAuth2 Configuration

```java
@Configuration
@EnableWebFluxSecurity
public class OAuth2SecurityConfig {

    @Bean
    public SecurityWebFilterChain oauth2SecurityFilterChain(ServerHttpSecurity http) {
        return http
            .authorizeExchange(exchanges -> exchanges
                .pathMatchers("/", "/login/**", "/oauth2/**").permitAll()
                .anyExchange().authenticated()
            )
            .oauth2Login(Customizer.withDefaults())
            .oauth2Client(Customizer.withDefaults())
            .build();
    }

    @Bean
    public ReactiveOAuth2AuthorizedClientManager authorizedClientManager(
            ReactiveClientRegistrationRepository clientRegistrationRepository,
            ServerOAuth2AuthorizedClientRepository authorizedClientRepository) {

        ReactiveOAuth2AuthorizedClientProvider authorizedClientProvider =
            ReactiveOAuth2AuthorizedClientProviderBuilder.builder()
                .authorizationCode()
                .refreshToken()
                .clientCredentials()
                .build();

        DefaultReactiveOAuth2AuthorizedClientManager authorizedClientManager =
            new DefaultReactiveOAuth2AuthorizedClientManager(
                clientRegistrationRepository,
                authorizedClientRepository);

        authorizedClientManager.setAuthorizedClientProvider(authorizedClientProvider);

        return authorizedClientManager;
    }
}
```

### OAuth2 WebClient Configuration

```java
@Configuration
@RequiredArgsConstructor
public class OAuth2WebClientConfig {

    private final ReactiveOAuth2AuthorizedClientManager authorizedClientManager;

    @Bean
    public WebClient oauth2WebClient() {
        ServerOAuth2AuthorizedClientExchangeFilterFunction oauth2Client =
            new ServerOAuth2AuthorizedClientExchangeFilterFunction(authorizedClientManager);

        oauth2Client.setDefaultClientRegistrationId("google");

        return WebClient.builder()
            .filter(oauth2Client)
            .build();
    }

    @Bean
    public WebClient clientCredentialsWebClient() {
        ServerOAuth2AuthorizedClientExchangeFilterFunction oauth2Client =
            new ServerOAuth2AuthorizedClientExchangeFilterFunction(authorizedClientManager);

        oauth2Client.setDefaultClientRegistrationId("internal-api");

        return WebClient.builder()
            .baseUrl("https://internal-api.example.com")
            .filter(oauth2Client)
            .build();
    }
}
```

### OAuth2 Token Service

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OAuth2TokenService {

    private final ReactiveOAuth2AuthorizedClientManager authorizedClientManager;

    public Mono<String> getAccessToken(String clientRegistrationId) {
        OAuth2AuthorizeRequest authorizeRequest = OAuth2AuthorizeRequest
            .withClientRegistrationId(clientRegistrationId)
            .principal("system")
            .build();

        return authorizedClientManager.authorize(authorizeRequest)
            .map(OAuth2AuthorizedClient::getAccessToken)
            .map(OAuth2AccessToken::getTokenValue)
            .doOnError(e -> log.error("Failed to get access token for {}",
                clientRegistrationId, e));
    }

    public Mono<OAuth2AuthorizedClient> getAuthorizedClient(
            String clientRegistrationId,
            Authentication authentication) {

        OAuth2AuthorizeRequest authorizeRequest = OAuth2AuthorizeRequest
            .withClientRegistrationId(clientRegistrationId)
            .principal(authentication)
            .build();

        return authorizedClientManager.authorize(authorizeRequest);
    }
}
```

### OAuth2 User Service

```java
@Service
@RequiredArgsConstructor
public class CustomReactiveOAuth2UserService
        implements ReactiveOAuth2UserService<OAuth2UserRequest, OAuth2User> {

    private final ReactiveUserRepository userRepository;
    private final DefaultReactiveOAuth2UserService delegate = new DefaultReactiveOAuth2UserService();

    @Override
    public Mono<OAuth2User> loadUser(OAuth2UserRequest userRequest) {
        return delegate.loadUser(userRequest)
            .flatMap(oauth2User -> processOAuth2User(userRequest, oauth2User));
    }

    private Mono<OAuth2User> processOAuth2User(
            OAuth2UserRequest userRequest,
            OAuth2User oauth2User) {

        String registrationId = userRequest.getClientRegistration().getRegistrationId();
        String email = extractEmail(oauth2User, registrationId);

        return userRepository.findByEmail(email)
            .switchIfEmpty(createNewUser(oauth2User, registrationId))
            .map(user -> new CustomOAuth2User(oauth2User, user));
    }

    private String extractEmail(OAuth2User oauth2User, String registrationId) {
        return switch (registrationId) {
            case "google" -> oauth2User.getAttribute("email");
            case "github" -> oauth2User.getAttribute("email");
            case "facebook" -> oauth2User.getAttribute("email");
            default -> throw new OAuth2AuthenticationException("Unknown provider: " + registrationId);
        };
    }

    private Mono<User> createNewUser(OAuth2User oauth2User, String registrationId) {
        User user = User.builder()
            .email(extractEmail(oauth2User, registrationId))
            .name(oauth2User.getAttribute("name"))
            .provider(registrationId)
            .providerId(oauth2User.getName())
            .roles(Set.of("USER"))
            .build();

        return userRepository.save(user);
    }
}

public class CustomOAuth2User implements OAuth2User {

    private final OAuth2User oauth2User;
    private final User user;

    @Override
    public Map<String, Object> getAttributes() {
        return oauth2User.getAttributes();
    }

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return user.getRoles().stream()
            .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
            .collect(Collectors.toList());
    }

    @Override
    public String getName() {
        return user.getEmail();
    }

    public User getUser() {
        return user;
    }
}
```

## Method-Level Security

### Enabling Method Security

```java
@Configuration
@EnableReactiveMethodSecurity
public class MethodSecurityConfig {
    // Configuration is handled by the annotation
}
```

### @PreAuthorize Patterns

```java
@Service
@RequiredArgsConstructor
public class SecuredUserService {

    private final ReactiveUserRepository userRepository;

    // Simple role check
    @PreAuthorize("hasRole('ADMIN')")
    public Flux<User> findAllUsers() {
        return userRepository.findAll();
    }

    // Multiple roles
    @PreAuthorize("hasAnyRole('ADMIN', 'MANAGER')")
    public Mono<User> updateUser(String id, UpdateUserRequest request) {
        return userRepository.findById(id)
            .map(user -> applyUpdates(user, request))
            .flatMap(userRepository::save);
    }

    // Permission-based
    @PreAuthorize("hasAuthority('USER_READ')")
    public Mono<User> findById(String id) {
        return userRepository.findById(id);
    }

    // SpEL expression with authentication
    @PreAuthorize("authentication.name == #userId or hasRole('ADMIN')")
    public Mono<UserProfile> getUserProfile(String userId) {
        return userRepository.findById(userId)
            .map(UserMapper::toProfile);
    }

    // Complex expression
    @PreAuthorize("@securityService.canAccessUser(authentication, #userId)")
    public Mono<User> getUser(String userId) {
        return userRepository.findById(userId);
    }

    // With return value check
    @PostAuthorize("returnObject.departmentId == authentication.principal.departmentId or hasRole('ADMIN')")
    public Mono<User> findUserWithDepartmentCheck(String id) {
        return userRepository.findById(id);
    }
}
```

### Custom Security Service for SpEL

```java
@Service("securityService")
@RequiredArgsConstructor
public class SecurityExpressionService {

    private final TeamMembershipRepository teamMembershipRepository;

    public Mono<Boolean> canAccessUser(Authentication authentication, String userId) {
        if (hasRole(authentication, "ADMIN")) {
            return Mono.just(true);
        }

        // Check if same user
        if (authentication.getName().equals(userId)) {
            return Mono.just(true);
        }

        // Check if manager of user
        return isManagerOf(authentication.getName(), userId);
    }

    public Mono<Boolean> canAccessProject(Authentication authentication, String projectId) {
        if (hasRole(authentication, "ADMIN")) {
            return Mono.just(true);
        }

        String userId = authentication.getName();
        return teamMembershipRepository.isMemberOfProject(userId, projectId);
    }

    public Mono<Boolean> canModifyResource(Authentication authentication, String resourceId) {
        return Mono.deferContextual(ctx -> {
            // Access context if needed
            String requestId = ctx.getOrDefault("requestId", "unknown");
            log.debug("Checking access for request: {}", requestId);

            return checkResourceOwnership(authentication.getName(), resourceId);
        });
    }

    private boolean hasRole(Authentication authentication, String role) {
        return authentication.getAuthorities().stream()
            .anyMatch(a -> a.getAuthority().equals("ROLE_" + role));
    }

    private Mono<Boolean> isManagerOf(String managerId, String userId) {
        return teamMembershipRepository.isManager(managerId, userId);
    }

    private Mono<Boolean> checkResourceOwnership(String userId, String resourceId) {
        return resourceRepository.findById(resourceId)
            .map(resource -> resource.getOwnerId().equals(userId))
            .defaultIfEmpty(false);
    }
}
```

### @PostFilter for Collections

```java
@Service
public class FilteredDataService {

    // Filter results based on security context
    @PostFilter("filterObject.departmentId == authentication.principal.departmentId or hasRole('ADMIN')")
    public Flux<Document> findDocuments() {
        return documentRepository.findAll();
    }

    // Complex filtering
    @PostFilter("@securityService.canViewDocument(authentication, filterObject)")
    public Flux<Document> searchDocuments(String query) {
        return documentRepository.search(query);
    }
}
```

### Reactive Method Security with Custom Voter

```java
@Configuration
@EnableReactiveMethodSecurity
public class CustomMethodSecurityConfig {

    @Bean
    public ReactiveMethodSecurityConfigurer methodSecurityConfigurer() {
        return new ReactiveMethodSecurityConfigurer() {
            @Override
            public void customize(DelegatingReactiveAuthorizationManager.Builder builder) {
                builder.add(new ResourceOwnershipAuthorizationManager());
            }
        };
    }
}

public class ResourceOwnershipAuthorizationManager
        implements ReactiveAuthorizationManager<MethodInvocation> {

    @Override
    public Mono<AuthorizationDecision> check(
            Mono<Authentication> authentication,
            MethodInvocation invocation) {

        return authentication
            .filter(auth -> auth.isAuthenticated())
            .flatMap(auth -> {
                // Extract resource ID from method arguments
                Object[] args = invocation.getArguments();
                if (args.length > 0 && args[0] instanceof String resourceId) {
                    return checkOwnership(auth, resourceId);
                }
                return Mono.just(new AuthorizationDecision(false));
            })
            .defaultIfEmpty(new AuthorizationDecision(false));
    }

    private Mono<AuthorizationDecision> checkOwnership(Authentication auth, String resourceId) {
        // Implementation for checking ownership
        return Mono.just(new AuthorizationDecision(true));
    }
}
```

## CORS Configuration

### Basic CORS Configuration

```java
@Configuration
@EnableWebFlux
public class CorsConfig implements WebFluxConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
            .allowedOrigins("https://example.com", "https://app.example.com")
            .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
            .allowedHeaders("*")
            .exposedHeaders("Authorization", "X-Request-Id")
            .allowCredentials(true)
            .maxAge(3600);
    }
}
```

### CORS with Security

```java
@Configuration
@EnableWebFluxSecurity
public class SecurityWithCorsConfig {

    @Bean
    public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
        return http
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .csrf(ServerHttpSecurity.CsrfSpec::disable)
            .authorizeExchange(exchanges -> exchanges
                .anyExchange().authenticated()
            )
            .build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOrigins(List.of(
            "https://example.com",
            "https://app.example.com"
        ));
        configuration.setAllowedMethods(List.of(
            "GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"
        ));
        configuration.setAllowedHeaders(List.of("*"));
        configuration.setExposedHeaders(List.of(
            "Authorization",
            "X-Request-Id",
            "X-Total-Count"
        ));
        configuration.setAllowCredentials(true);
        configuration.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", configuration);
        return source;
    }
}
```

### Dynamic CORS Configuration

```java
@Component
@RequiredArgsConstructor
public class DynamicCorsConfigurationSource implements CorsConfigurationSource {

    private final AllowedOriginsService allowedOriginsService;

    @Override
    public CorsConfiguration getCorsConfiguration(ServerWebExchange exchange) {
        String requestOrigin = exchange.getRequest().getHeaders().getOrigin();

        CorsConfiguration config = new CorsConfiguration();

        // Dynamically check if origin is allowed
        if (allowedOriginsService.isAllowed(requestOrigin)) {
            config.setAllowedOrigins(List.of(requestOrigin));
        }

        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);
        config.setMaxAge(3600L);

        return config;
    }
}

@Service
public class AllowedOriginsService {

    private final Set<String> allowedOrigins = ConcurrentHashMap.newKeySet();
    private final AllowedOriginRepository repository;

    @PostConstruct
    public void loadAllowedOrigins() {
        repository.findAll()
            .map(AllowedOrigin::getOrigin)
            .doOnNext(allowedOrigins::add)
            .subscribe();
    }

    public boolean isAllowed(String origin) {
        if (origin == null) {
            return false;
        }
        return allowedOrigins.contains(origin);
    }

    public Mono<Void> addAllowedOrigin(String origin) {
        return repository.save(new AllowedOrigin(origin))
            .doOnSuccess(saved -> allowedOrigins.add(origin))
            .then();
    }
}
```

### CORS WebFilter

```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class CorsWebFilter implements WebFilter {

    private static final Set<String> ALLOWED_ORIGINS = Set.of(
        "https://example.com",
        "https://app.example.com"
    );

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();
        ServerHttpResponse response = exchange.getResponse();

        String origin = request.getHeaders().getOrigin();

        if (origin != null && ALLOWED_ORIGINS.contains(origin)) {
            response.getHeaders().add(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, origin);
            response.getHeaders().add(HttpHeaders.ACCESS_CONTROL_ALLOW_CREDENTIALS, "true");
            response.getHeaders().add(HttpHeaders.ACCESS_CONTROL_ALLOW_METHODS,
                "GET, POST, PUT, DELETE, OPTIONS");
            response.getHeaders().add(HttpHeaders.ACCESS_CONTROL_ALLOW_HEADERS, "*");
            response.getHeaders().add(HttpHeaders.ACCESS_CONTROL_EXPOSE_HEADERS,
                "Authorization, X-Request-Id");
            response.getHeaders().add(HttpHeaders.ACCESS_CONTROL_MAX_AGE, "3600");
        }

        // Handle preflight
        if (request.getMethod() == HttpMethod.OPTIONS) {
            response.setStatusCode(HttpStatus.OK);
            return Mono.empty();
        }

        return chain.filter(exchange);
    }
}
```

## Security Filters

### Rate Limiting Security Filter

```java
@Component
@RequiredArgsConstructor
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
public class RateLimitSecurityFilter implements WebFilter {

    private final RateLimiterService rateLimiter;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        return ReactiveSecurityContextHolder.getContext()
            .map(ctx -> ctx.getAuthentication().getName())
            .defaultIfEmpty(getClientIp(exchange))
            .flatMap(identifier -> rateLimiter.checkLimit(identifier))
            .flatMap(allowed -> {
                if (allowed) {
                    return chain.filter(exchange);
                }
                return handleRateLimitExceeded(exchange);
            });
    }

    private String getClientIp(ServerWebExchange exchange) {
        String forwarded = exchange.getRequest().getHeaders().getFirst("X-Forwarded-For");
        if (forwarded != null) {
            return forwarded.split(",")[0].trim();
        }
        InetSocketAddress address = exchange.getRequest().getRemoteAddress();
        return address != null ? address.getHostString() : "unknown";
    }

    private Mono<Void> handleRateLimitExceeded(ServerWebExchange exchange) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
        response.getHeaders().add("Retry-After", "60");
        return response.setComplete();
    }
}
```

### IP Whitelist Filter

```java
@Component
@RequiredArgsConstructor
public class IpWhitelistFilter implements WebFilter {

    private final IpWhitelistService whitelistService;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String path = exchange.getRequest().getPath().value();

        // Only apply to admin endpoints
        if (!path.startsWith("/api/admin")) {
            return chain.filter(exchange);
        }

        String clientIp = getClientIp(exchange);

        return whitelistService.isWhitelisted(clientIp)
            .flatMap(allowed -> {
                if (allowed) {
                    return chain.filter(exchange);
                }
                return handleForbidden(exchange, clientIp);
            });
    }

    private Mono<Void> handleForbidden(ServerWebExchange exchange, String clientIp) {
        log.warn("Access denied for IP: {}", clientIp);
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatus.FORBIDDEN);
        return response.setComplete();
    }
}
```

## Authentication Patterns

### Multi-Factor Authentication

```java
@Service
@RequiredArgsConstructor
public class MfaAuthenticationService {

    private final UserRepository userRepository;
    private final TotpService totpService;
    private final JwtTokenProvider tokenProvider;

    public Mono<MfaAuthResponse> initiateLogin(LoginRequest request) {
        return userRepository.findByEmail(request.getEmail())
            .filter(user -> passwordEncoder.matches(request.getPassword(), user.getPassword()))
            .switchIfEmpty(Mono.error(new BadCredentialsException("Invalid credentials")))
            .flatMap(user -> {
                if (user.isMfaEnabled()) {
                    // Generate partial token for MFA step
                    String mfaToken = tokenProvider.generateMfaToken(user);
                    return Mono.just(MfaAuthResponse.requiresMfa(mfaToken));
                }
                // No MFA, return full tokens
                return Mono.just(MfaAuthResponse.success(
                    tokenProvider.generateToken(user),
                    tokenProvider.generateRefreshToken(user)
                ));
            });
    }

    public Mono<AuthResponse> completeMfaLogin(MfaVerifyRequest request) {
        return tokenProvider.validateMfaToken(request.getMfaToken())
            .filter(valid -> valid)
            .switchIfEmpty(Mono.error(new BadCredentialsException("Invalid MFA token")))
            .then(tokenProvider.getUserIdFromMfaToken(request.getMfaToken()))
            .flatMap(userRepository::findById)
            .filter(user -> totpService.verifyCode(user.getMfaSecret(), request.getCode()))
            .switchIfEmpty(Mono.error(new BadCredentialsException("Invalid MFA code")))
            .map(user -> AuthResponse.builder()
                .accessToken(tokenProvider.generateToken(user))
                .refreshToken(tokenProvider.generateRefreshToken(user))
                .build());
    }
}
```

### API Key Authentication

```java
@Component
@RequiredArgsConstructor
public class ApiKeyAuthenticationFilter implements WebFilter {

    private final ApiKeyService apiKeyService;
    private static final String API_KEY_HEADER = "X-API-Key";

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String path = exchange.getRequest().getPath().value();

        // Only for API endpoints
        if (!path.startsWith("/api/external")) {
            return chain.filter(exchange);
        }

        return Mono.justOrEmpty(exchange.getRequest().getHeaders().getFirst(API_KEY_HEADER))
            .switchIfEmpty(Mono.error(new AuthenticationCredentialsNotFoundException("API key required")))
            .flatMap(apiKeyService::validateAndGetClient)
            .flatMap(client -> {
                Authentication auth = new ApiKeyAuthenticationToken(client);
                return chain.filter(exchange)
                    .contextWrite(ReactiveSecurityContextHolder.withAuthentication(auth));
            })
            .onErrorResume(e -> handleUnauthorized(exchange, e.getMessage()));
    }

    private Mono<Void> handleUnauthorized(ServerWebExchange exchange, String message) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatus.UNAUTHORIZED);
        return response.setComplete();
    }
}

public class ApiKeyAuthenticationToken extends AbstractAuthenticationToken {

    private final ApiClient client;

    public ApiKeyAuthenticationToken(ApiClient client) {
        super(client.getAuthorities());
        this.client = client;
        setAuthenticated(true);
    }

    @Override
    public Object getCredentials() {
        return null;
    }

    @Override
    public Object getPrincipal() {
        return client;
    }
}
```

## Authorization Patterns

### Resource-Based Authorization

```java
@Service
@RequiredArgsConstructor
public class ResourceAuthorizationService {

    private final ResourceRepository resourceRepository;

    public Mono<Boolean> canRead(Authentication auth, String resourceId) {
        return resourceRepository.findById(resourceId)
            .map(resource -> {
                String userId = auth.getName();

                // Owner can always read
                if (resource.getOwnerId().equals(userId)) {
                    return true;
                }

                // Check if user has read permission
                return resource.getReadPermissions().contains(userId) ||
                       hasAdminRole(auth);
            })
            .defaultIfEmpty(false);
    }

    public Mono<Boolean> canWrite(Authentication auth, String resourceId) {
        return resourceRepository.findById(resourceId)
            .map(resource -> {
                String userId = auth.getName();

                // Owner can always write
                if (resource.getOwnerId().equals(userId)) {
                    return true;
                }

                // Check if user has write permission
                return resource.getWritePermissions().contains(userId) ||
                       hasAdminRole(auth);
            })
            .defaultIfEmpty(false);
    }

    public Mono<Boolean> canDelete(Authentication auth, String resourceId) {
        return resourceRepository.findById(resourceId)
            .map(resource -> {
                String userId = auth.getName();

                // Only owner or admin can delete
                return resource.getOwnerId().equals(userId) || hasAdminRole(auth);
            })
            .defaultIfEmpty(false);
    }

    private boolean hasAdminRole(Authentication auth) {
        return auth.getAuthorities().stream()
            .anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));
    }
}

@RestController
@RequestMapping("/api/resources")
@RequiredArgsConstructor
public class ResourceController {

    private final ResourceService resourceService;
    private final ResourceAuthorizationService authService;

    @GetMapping("/{id}")
    public Mono<Resource> getResource(@PathVariable String id) {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .flatMap(auth -> authService.canRead(auth, id)
                .filter(allowed -> allowed)
                .switchIfEmpty(Mono.error(new AccessDeniedException("Cannot read resource")))
                .then(resourceService.findById(id)));
    }

    @PutMapping("/{id}")
    public Mono<Resource> updateResource(
            @PathVariable String id,
            @RequestBody UpdateResourceRequest request) {

        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .flatMap(auth -> authService.canWrite(auth, id)
                .filter(allowed -> allowed)
                .switchIfEmpty(Mono.error(new AccessDeniedException("Cannot update resource")))
                .then(resourceService.update(id, request)));
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public Mono<Void> deleteResource(@PathVariable String id) {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .flatMap(auth -> authService.canDelete(auth, id)
                .filter(allowed -> allowed)
                .switchIfEmpty(Mono.error(new AccessDeniedException("Cannot delete resource")))
                .then(resourceService.deleteById(id)));
    }
}
```

### Attribute-Based Access Control (ABAC)

```java
@Service
@RequiredArgsConstructor
public class AbacAuthorizationService {

    private final PolicyRepository policyRepository;
    private final AttributeResolver attributeResolver;

    public Mono<Boolean> isAuthorized(
            Authentication auth,
            String action,
            String resourceType,
            String resourceId) {

        return Mono.zip(
                getSubjectAttributes(auth),
                getResourceAttributes(resourceType, resourceId),
                getEnvironmentAttributes()
            )
            .flatMap(tuple -> evaluatePolicies(
                action,
                tuple.getT1(),
                tuple.getT2(),
                tuple.getT3()
            ));
    }

    private Mono<Map<String, Object>> getSubjectAttributes(Authentication auth) {
        return Mono.fromCallable(() -> {
            Map<String, Object> attrs = new HashMap<>();
            attrs.put("userId", auth.getName());
            attrs.put("roles", auth.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .collect(Collectors.toList()));

            if (auth.getPrincipal() instanceof UserDetails user) {
                attrs.put("department", user.getDepartment());
                attrs.put("clearanceLevel", user.getClearanceLevel());
            }

            return attrs;
        });
    }

    private Mono<Map<String, Object>> getResourceAttributes(String resourceType, String resourceId) {
        return attributeResolver.resolveResourceAttributes(resourceType, resourceId);
    }

    private Mono<Map<String, Object>> getEnvironmentAttributes() {
        return Mono.fromCallable(() -> {
            Map<String, Object> attrs = new HashMap<>();
            attrs.put("currentTime", Instant.now());
            attrs.put("dayOfWeek", LocalDate.now().getDayOfWeek());
            attrs.put("isBusinessHours", isBusinessHours());
            return attrs;
        });
    }

    private Mono<Boolean> evaluatePolicies(
            String action,
            Map<String, Object> subjectAttrs,
            Map<String, Object> resourceAttrs,
            Map<String, Object> envAttrs) {

        return policyRepository.findByAction(action)
            .filter(policy -> policy.evaluate(subjectAttrs, resourceAttrs, envAttrs))
            .hasElements();
    }

    private boolean isBusinessHours() {
        LocalTime now = LocalTime.now();
        return now.isAfter(LocalTime.of(9, 0)) && now.isBefore(LocalTime.of(18, 0));
    }
}
```

### Hierarchical Role Authorization

```java
@Service
public class HierarchicalRoleService {

    private final Map<String, Set<String>> roleHierarchy = Map.of(
        "ADMIN", Set.of("MANAGER", "USER", "VIEWER"),
        "MANAGER", Set.of("USER", "VIEWER"),
        "USER", Set.of("VIEWER"),
        "VIEWER", Set.of()
    );

    public Mono<Boolean> hasRole(Authentication auth, String requiredRole) {
        return Mono.fromCallable(() -> {
            Set<String> userRoles = auth.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .map(r -> r.replace("ROLE_", ""))
                .collect(Collectors.toSet());

            // Check direct role
            if (userRoles.contains(requiredRole)) {
                return true;
            }

            // Check inherited roles
            return userRoles.stream()
                .map(roleHierarchy::get)
                .filter(Objects::nonNull)
                .flatMap(Set::stream)
                .anyMatch(r -> r.equals(requiredRole));
        });
    }

    public Mono<Set<String>> getEffectiveRoles(Authentication auth) {
        return Mono.fromCallable(() -> {
            Set<String> userRoles = auth.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .map(r -> r.replace("ROLE_", ""))
                .collect(Collectors.toSet());

            Set<String> effectiveRoles = new HashSet<>(userRoles);

            userRoles.forEach(role -> {
                Set<String> inherited = roleHierarchy.get(role);
                if (inherited != null) {
                    effectiveRoles.addAll(inherited);
                }
            });

            return effectiveRoles;
        });
    }
}
```
