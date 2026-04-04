---
name: summer-security
description: Summer Framework security — APISIX auth integration with X-Userinfo header, @AuthRoles annotation for role definitions, SecurityWebFilterChain config, ReactiveKeycloakClient for Keycloak resource API, KeycloakRoleSynchronizer, KeycloakException error mapping, and group-role authorization (0.2.4+).
triggers:
  natural: ["auth roles", "keycloak client", "summer security"]
  code: ["@AuthRoles", "ReactiveKeycloakClient", "f8a.security"]
requires: ["summer-core", "spring-security"]
---

# Summer Security — APISIX, Keycloak & Roles

**Gate:** Verify summer-core is loaded and io.f8a.summer:summer-platform is in build.gradle before proceeding.

**Modules:** `summer-security-autoconfigure` | `summer-keycloak`

## APISIX Auth Integration

APISIX gateway validates JWT, forwards `X-Userinfo` header (Base64 JSON). Summer decodes it into `Member`.

**Version note:** `UserInfoAuthenticationConverter` return type changed from a synchronous value to `Mono` in 0.2.4 (BREAKING). Ensure any custom converter implementations return `Mono`.

```java
@Configuration
@EnableWebFluxSecurity
@EnableReactiveMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {
    final ReactiveSummerHttpSecurityCustomizer summerCustomizer;
    final ReactiveApisixCustomizer apisixCustomizer;

    @Bean
    public SecurityWebFilterChain securityFilterChain(ServerHttpSecurity http) {
        summerCustomizer.customize(http);  // CORS all, CSRF off, stateless
        apisixCustomizer.customize(http);  // X-Userinfo auth
        return http.authorizeExchange(auth -> auth
            .pathMatchers("/actuator/**").permitAll()
            .anyExchange().authenticated()).build();
    }
}
```

Enforce with `@PreAuthorize("hasAnyRole(@roles.USER_VIEW)")`.

## @AuthRoles — Role Definitions

Role string format: `service-name:resource:action` (e.g., `my-svc:user:view`).

```java
@AuthRoles(resources = {
    @ResourceDef(code = "my-svc", name = "My Service",
        attributes = @AttributeDef(key = "tier", value = "premium"),
        features = @FeatureDef(code = "user-mgmt", name = "User Management"))
})
@Component
public class Roles {
    public static final String USER_VIEW = "my-svc:user:view";
    public static final String USER_EDIT = "my-svc:user:edit";
}
```

Annotations (in `summer-core`): `@AuthRoles` (resources), `@ResourceDef` (code, name, description, attributes, features), `@AttributeDef` (key, value), `@FeatureDef` (code, name, description).

## ReactiveKeycloakClient

Resource-based API mirroring keycloak-admin-client SPI. Self-creates `WebClient` from `KeycloakConfig.serverUrl`.

```java
var config = new KeycloakConfig();
config.setServerUrl("https://keycloak.example.com");
config.setRealm("my-realm");
config.setClientId("admin-cli");
config.setClientSecret("secret");
var keycloak = new ReactiveKeycloakClient(config);
```

**Navigation:** `keycloak.users()` / `.clients()` / `.groups()` / `.realm()` / `.tokenResource()` / `.tokenProvider()`

For complete ReactiveKeycloakClient API, see `references/keycloak-error-map.md`.

## KeycloakRoleSynchronizer

`ApplicationRunner` at startup: scans `@AuthRoles` -> syncs clients, roles, features (JSON attribute), custom attributes to Keycloak.

## Group-Role Authorization (0.2.4+)

Alternative authorization strategy — resolves roles from group membership instead of `resource_access` JWT claim.

```yaml
f8a:
  security:
    apisix:
      resource-server:
        keycloak:
          server-url: https://kc.example.com
          realm: my-realm
          client-id: admin-cli
          client-secret: secret
        group-role-authorization:
          enabled: true
          claim-name: role_groups
          l1:
            ttl: 60s
          l2:                       # omit = L1-only mode
            ttl: 5m
            invalidation-channel: "group-role-changes"
            key-prefix: "auth-group-role:"
```

Key classes: `GroupRoleResolver` (L1→L2→L3 cache), `GroupRoleAuthenticationConverter`, `GroupRoleFetcher` (default:
Keycloak group-by-path), `GroupRoleInvalidator` (Redis pub/sub).

## Config

```yaml
f8a:
  security:
    apisix:
      resource-server:
        enabled: true
        role-hierarchy: "ROLE_ADMIN > ROLE_USER"
        keycloak:                  # shared block (0.2.4+)
          server-url: ${KEYCLOAK_URL}
          realm: master
          client-id: admin-cli
          client-secret: ${KEYCLOAK_SECRET}
        sync-role:
          enabled: true
        group-role-authorization:
          enabled: false           # 0.2.4+ alternative to resource_access
```

## Version Notes

- **0.2.1:** Renamed to `summer-jwt-resource-server`; added `summer-apikey-resource-server`
- **0.2.3:** `sync-role.enable` → `sync-role.enabled`; `KeycloakException` expanded to ~58 mappings
- **0.2.4:** Keycloak config moved to shared `keycloak` block (BREAKING); `UserInfoAuthenticationConverter` returns `Mono` (BREAKING); group-role authorization added

See `references/keycloak-error-map.md` for the full KeycloakException error mapping table and Keycloak resource API.

## Rules

- Always use `summerCustomizer.customize(http)` + `apisixCustomizer.customize(http)` in SecurityWebFilterChain — never manually configure CORS/CSRF/session for Summer projects.
- Always define roles using `@AuthRoles` + `@ResourceDef` — never hardcode role strings outside the Roles class.
- Always use `@PreAuthorize("hasAnyRole(@roles.XXX)")` for endpoint authorization — never rely solely on path matchers.
- Never expose Keycloak client secrets in application.yml — use environment variables or Vault.
- Always check Summer version before using group-role authorization — requires 0.2.4+.

## Related Skills

- **summer-core** — Shared types (Member, CallerAware) decoded from X-Userinfo
- **summer-test** — Mock X-Userinfo header for testing @AuthRoles-protected endpoints
- **spring-security** — General Spring Security patterns, JWT, CORS
- **summer-rest** — BaseController + RequestHandler secured by @PreAuthorize
