# OAuth2 / OIDC Patterns — Reference

## OAuth2 Resource Server (JWT)

```java
@Configuration @EnableWebFluxSecurity
public class SecurityConfig {

    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
        return http
            .csrf(ServerHttpSecurity.CsrfSpec::disable)  // stateless API
            .authorizeExchange(auth -> auth
                .pathMatchers("/actuator/health/**").permitAll()
                .pathMatchers("/api/admin/**").hasRole("ADMIN")
                .anyExchange().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtDecoder(jwtDecoder()))
            )
            .build();
    }

    @Bean
    public ReactiveJwtDecoder jwtDecoder() {
        NimbusReactiveJwtDecoder decoder = NimbusReactiveJwtDecoder
            .withJwkSetUri("${spring.security.oauth2.resourceserver.jwt.jwk-set-uri}")
            .build();
        // Validate audience
        OAuth2TokenValidator<Jwt> audienceValidator = token ->
            token.getAudience().contains("my-api")
                ? OAuth2TokenValidatorResult.success()
                : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_audience"));
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
            JwtValidators.createDefault(), audienceValidator));
        return decoder;
    }
}
```

## Application Properties

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://auth.example.com/realms/my-realm
          jwk-set-uri: https://auth.example.com/realms/my-realm/protocol/openid-connect/certs
```

## Client Credentials Flow (Service-to-Service)

```java
@Bean
public WebClient authorizedWebClient(ReactiveOAuth2AuthorizedClientManager clientManager) {
    ServerOAuth2AuthorizedClientExchangeFilterFunction filter =
        new ServerOAuth2AuthorizedClientExchangeFilterFunction(clientManager);
    filter.setDefaultClientRegistrationId("my-service");
    return WebClient.builder().filter(filter).build();
}
```

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          my-service:
            provider: keycloak
            client-id: my-service
            client-secret: ${SERVICE_CLIENT_SECRET}
            authorization-grant-type: client_credentials
            scope: openid
        provider:
          keycloak:
            issuer-uri: https://auth.example.com/realms/my-realm
```

## Custom Principal Extraction

```java
@Bean
public ReactiveJwtAuthenticationConverter jwtAuthenticationConverter() {
    var converter = new ReactiveJwtAuthenticationConverter();
    converter.setJwtGrantedAuthoritiesConverter(jwt -> {
        Map<String, Object> realmAccess = jwt.getClaimAsMap("realm_access");
        @SuppressWarnings("unchecked")
        List<String> roles = (List<String>) realmAccess.get("roles");
        return Flux.fromIterable(roles)
            .map(role -> new SimpleGrantedAuthority("ROLE_" + role.toUpperCase()));
    });
    return converter;
}
```

## Spring Security 6.x Migration Notes

| Old (5.x) | New (6.x) | Notes |
|-----------|-----------|-------|
| `antMatchers()` | `requestMatchers()` | Method renamed |
| `authorizeRequests()` | `authorizeHttpRequests()` | MVC; WebFlux uses `authorizeExchange()` (unchanged) |
| `@Configuration` | `@Configuration(proxyBeanMethods=false)` | Performance optimization |
| `SecurityFilterChain` ordering | `@Order` required on multiple chains | No implicit ordering |

## Testing OAuth2

```java
@SpringBootTest @AutoConfigureWebTestClient
class SecuredEndpointTest {
    @Autowired WebTestClient webTestClient;

    @Test
    void shouldRejectWithoutToken() {
        webTestClient.get().uri("/api/orders")
            .exchange()
            .expectStatus().isUnauthorized();
    }

    @Test
    void shouldAcceptValidToken() {
        webTestClient.mutateWith(mockJwt()
                .jwt(jwt -> jwt.claim("sub", "user-1")
                    .claim("realm_access", Map.of("roles", List.of("user")))))
            .get().uri("/api/orders")
            .exchange()
            .expectStatus().isOk();
    }
}
```
