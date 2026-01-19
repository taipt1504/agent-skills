# Reactive Security Reference

## Table of Contents
- [ReactiveSecurityContextHolder](#reactivesecuritycontextholder)
- [JWT Authentication Reactive](#jwt-authentication-reactive)
- [OAuth2 Reactive Client](#oauth2-reactive-client)
- [Method-Level Security](#method-level-security)
- [CORS and CSRF](#cors-and-csrf)
- [Security Testing](#security-testing)

## ReactiveSecurityContextHolder

### Basic Usage

```java
@Service
@Slf4j
public class SecurityService {

    public Mono<String> getCurrentUsername() {
        return ReactiveSecurityContextHolder.getContext()
            .map(context -> context.getAuthentication())
            .filter(Authentication::isAuthenticated)
            .map(Authentication::getName)
            .switchIfEmpty(Mono.error(new UnauthorizedException("No user logged in")));
    }

    public Mono<UserPrincipal> getCurrentUser() {
        return ReactiveSecurityContextHolder.getContext()
            .map(SecurityContext::getAuthentication)
            .map(auth -> (UserPrincipal) auth.getPrincipal());
    }
}
```

### Context Propagation

```java
@Configuration
public class SecurityContextConfig {

    @PostConstruct
    public void enableContextPropagation() {
        // Essential so that Security Context is available in other threads
        Hooks.enableAutomaticContextPropagation();
    }
}

@Service
public class AsyncService {

    public Mono<Void> processAsync() {
        return ReactiveSecurityContextHolder.getContext()
            .flatMap(context -> {
                // Context is available here
                Authentication auth = context.getAuthentication();

                return Mono.fromRunnable(() -> {
                    // Context might be lost here without Reactor Context Propagation
                    log.info("Processing for user: {}", auth.getName());
                }).subscribeOn(Schedulers.boundedElastic());
            });
    }
}
```

### Custom Repository

```java
@Component
public class ServerSecurityContextRepositoryImpl implements ServerSecurityContextRepository {

    private final JwtTokenProvider tokenProvider;
    private final AuthenticationManager authenticationManager;

    @Override
    public Mono<Void> save(ServerWebExchange exchange, SecurityContext context) {
        return Mono.empty(); // Stateless, no session save
    }

    @Override
    public Mono<SecurityContext> load(ServerWebExchange exchange) {
        return Mono.justOrEmpty(exchange.getRequest().getHeaders().getFirst(HttpHeaders.AUTHORIZATION))
            .filter(authHeader -> authHeader.startsWith("Bearer "))
            .map(authHeader -> authHeader.substring(7))
            .flatMap(token -> {
                Authentication auth = tokenProvider.getAuthentication(token);
                return authenticationManager.authenticate(auth)
                    .map(SecurityContextImpl::new);
            });
    }
}
```

## JWT Authentication Reactive

### Token Provider

```java
@Component
@Slf4j
public class JwtTokenProvider {

    @Value("${app.jwt.secret}")
    private String secretKey;

    @Value("${app.jwt.expiration}")
    private long validityInMilliseconds;

    private SecretKey key;

    @PostConstruct
    public void init() {
        this.key = Keys.hmacShaKeyFor(Base64.getEncoder().encode(secretKey.getBytes()));
    }

    public String createToken(Authentication authentication) {
        String username = authentication.getName();
        Collection<? extends GrantedAuthority> authorities = authentication.getAuthorities();
        Claims claims = Jwts.claims().setSubject(username);
        claims.put("auth", authorities.stream()
            .map(GrantedAuthority::getAuthority)
            .collect(Collectors.toList()));

        Date now = new Date();
        Date validity = new Date(now.getTime() + validityInMilliseconds);

        return Jwts.builder()
            .setClaims(claims)
            .setIssuedAt(now)
            .setExpiration(validity)
            .signWith(key, SignatureAlgorithm.HS256)
            .compact();
    }

    public Authentication getAuthentication(String token) {
        Claims claims = Jwts.parserBuilder()
            .setSigningKey(key)
            .build()
            .parseClaimsJws(token)
            .getBody();

        Collection<? extends GrantedAuthority> authorities =
            Arrays.stream(claims.get("auth").toString().split(","))
                .map(SimpleGrantedAuthority::new)
                .collect(Collectors.toList());

        User principal = new User(claims.getSubject(), "", authorities);

        return new UsernamePasswordAuthenticationToken(principal, token, authorities);
    }

    public boolean validateToken(String token) {
        try {
            Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            log.info("Invalid JWT token: {}", e.getMessage());
            return false;
        }
    }
}
```

### Authentication Manager

```java
@Component
@RequiredArgsConstructor
public class ReactiveAuthenticationManagerImpl implements ReactiveAuthenticationManager {

    private final ReactiveUserDetailsService userDetailsService;
    private final PasswordEncoder passwordEncoder;

    @Override
    public Mono<Authentication> authenticate(Authentication authentication) {
        String username = authentication.getName();
        String password = authentication.getCredentials().toString();

        return userDetailsService.findByUsername(username)
            .filter(userDetails -> passwordEncoder.matches(password, userDetails.getPassword()))
            .map(userDetails -> new UsernamePasswordAuthenticationToken(
                userDetails,
                password,
                userDetails.getAuthorities()
            ))
            .switchIfEmpty(Mono.error(new BadCredentialsException("Invalid credentials")));
    }
}
```

### JWT Filter

```java
@Component
@RequiredArgsConstructor
public class JwtTokenAuthenticationFilter implements WebFilter {

    private final JwtTokenProvider tokenProvider;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String token = resolveToken(exchange.getRequest());
        if (token != null && tokenProvider.validateToken(token)) {
            Authentication auth = tokenProvider.getAuthentication(token);
            return chain.filter(exchange)
                .contextWrite(ReactiveSecurityContextHolder.withAuthentication(auth));
        }
        return chain.filter(exchange);
    }

    private String resolveToken(ServerHttpRequest request) {
        String bearerToken = request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
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

    private final ReactiveAuthenticationManager authenticationManager;
    private final SecurityContextRepository securityContextRepository;

    @Bean
    public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(ServerHttpSecurity.CsrfSpec::disable)
            .formLogin(ServerHttpSecurity.FormLoginSpec::disable)
            .httpBasic(ServerHttpSecurity.HttpBasicSpec::disable)
            .authenticationManager(authenticationManager)
            .securityContextRepository(securityContextRepository)
            .authorizeExchange(exchanges -> exchanges
                .pathMatchers(HttpMethod.OPTIONS).permitAll()
                .pathMatchers("/auth/**").permitAll()
                .pathMatchers("/public/**").permitAll()
                .pathMatchers("/actuator/**").hasRole("ADMIN")
                .anyExchange().authenticated()
            )
            .exceptionHandling(exceptionHandling -> exceptionHandling
                .authenticationEntryPoint((swe, e) -> 
                    Mono.fromRunnable(() -> swe.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED))
                )
                .accessDeniedHandler((swe, e) -> 
                    Mono.fromRunnable(() -> swe.getResponse().setStatusCode(HttpStatus.FORBIDDEN))
                )
            )
            .build();
    }
}
```

### Authentication Controller

```java
@RestController
@RequestMapping("/auth")
@RequiredArgsConstructor
public class AuthController {

    private final JwtTokenProvider tokenProvider;
    private final ReactiveAuthenticationManager authenticationManager;

    @PostMapping("/login")
    public Mono<ResponseEntity<AuthResponse>> login(@RequestBody AuthRequest request) {
        return authenticationManager
            .authenticate(new UsernamePasswordAuthenticationToken(request.getUsername(), request.getPassword()))
            .map(tokenProvider::createToken)
            .map(token -> ResponseEntity.ok(new AuthResponse(token)))
            .onErrorResume(BadCredentialsException.class, 
                e -> Mono.just(ResponseEntity.status(HttpStatus.UNAUTHORIZED).build()));
    }
}
```

## OAuth2 Reactive Client

### Configuration

```java
@Configuration
public class OAuth2ClientConfig {

    @Bean
    public SecurityWebFilterChain springSecurityFilterChain(ServerHttpSecurity http) {
        http
            .oauth2Client()
            .and()
            .authorizeExchange()
            .anyExchange().permitAll(); // Or authenticated() as needed

        return http.build();
    }
}
```

### WebClient with OAuth2

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient webClient(ReactiveOAuth2AuthorizedClientManager authorizedClientManager) {
        ServerOAuth2AuthorizedClientExchangeFilterFunction oauth2Client =
            new ServerOAuth2AuthorizedClientExchangeFilterFunction(authorizedClientManager);

        oauth2Client.setDefaultClientRegistrationId("my-client");

        return WebClient.builder()
            .filter(oauth2Client)
            .build();
    }

    @Bean
    public ReactiveOAuth2AuthorizedClientManager authorizedClientManager(
            ReactiveClientRegistrationRepository clientRegistrationRepository,
            ReactiveOAuth2AuthorizedClientService authorizedClientService) {

        ReactiveOAuth2AuthorizedClientProvider authorizedClientProvider =
            ReactiveOAuth2AuthorizedClientProviderBuilder.builder()
                .clientCredentials()
                .build();

        AuthorizedClientServiceReactiveOAuth2AuthorizedClientManager authorizedClientManager =
            new AuthorizedClientServiceReactiveOAuth2AuthorizedClientManager(
                clientRegistrationRepository, authorizedClientService);

        authorizedClientManager.setAuthorizedClientProvider(authorizedClientProvider);

        return authorizedClientManager;
    }
}
```

### Token Service

```java
@Service
@RequiredArgsConstructor
public class TokenService {

    private final ReactiveOAuth2AuthorizedClientManager authorizedClientManager;

    public Mono<String> getAccessToken() {
        return authorizedClientManager
            .authorize(OAuth2AuthorizeRequest
                .withClientRegistrationId("my-client")
                .principal("internal-service")
                .build())
            .map(OAuth2AuthorizedClient::getAccessToken)
            .map(OAuth2AccessToken::getTokenValue);
    }
}
```

## Method-Level Security

### Enabling

```java
@Configuration
@EnableReactiveMethodSecurity
public class MethodSecurityConfig {
}
```

### @PreAuthorize Patterns

```java
@Service
public class SecuredService {

    @PreAuthorize("hasRole('ADMIN')")
    public Mono<Void> deleteUser(String userId) {
        return userRepository.deleteById(userId);
    }

    @PreAuthorize("hasRole('USER') and #username == authentication.name")
    public Mono<User> updateProfile(String username, UserProfile profile) {
        return userRepository.findByUsername(username)
            .flatMap(user -> {
                user.setProfile(profile);
                return userRepository.save(user);
            });
    }

    @PreAuthorize("@permissionEvaluator.hasPermission(authentication, #resourceId, 'read')")
    public Mono<Resource> getResource(String resourceId) {
        return resourceRepository.findById(resourceId);
    }
}
```

### Custom Security Service

```java
@Service("customSecurity")
public class CustomSecurityService {

    public Mono<Boolean> checkOwnership(String resourceId, UserPrincipal principal) {
        return resourceRepository.findById(resourceId)
            .map(resource -> resource.getOwnerId().equals(principal.getId()));
    }
}

// Usage
// @PreAuthorize("@customSecurity.checkOwnership(#id, authentication.principal)")
// public Mono<Resource> getResource(String id) { ... }
```

### @PostFilter for Collections

```java
@Service
public class DocumentService {

    // Filters the returned Flux to only include documents the user owns
    // Note: This loads all data into memory first! Use with caution or small datasets.
    // For large datasets, filter in the database query instead.
    @PostFilter("filterObject.owner == authentication.name")
    public Flux<Document> getAllDocuments() {
        return documentRepository.findAll();
    }
}
```
