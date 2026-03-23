---
name: summer-security
description: >
  Summer Framework security — APISIX auth integration with X-Userinfo header,
  @AuthRoles annotation for role definitions, SecurityWebFilterChain config,
  ReactiveKeycloakClient for Keycloak resource API, KeycloakRoleSynchronizer,
  KeycloakException error mapping, and group-role authorization (0.2.4+).
triggers:
  - APISIX
  - "@AuthRoles"
  - "@ResourceDef"
  - ReactiveKeycloakClient
  - KeycloakException
  - SecurityWebFilterChain
  - f8a.security
  - sync-role
  - summer security
  - summer keycloak
  - keycloak client
  - X-Userinfo
  - GroupRoleResolver
  - group-role-authorization
---

# Summer Security — APISIX, Keycloak & Roles

**Modules:** `summer-security-autoconfigure` | `summer-keycloak`

## APISIX Auth Integration

APISIX gateway validates JWT, forwards `X-Userinfo` header (Base64 JSON). Summer decodes it into `Member`.

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

Key operations: `users().create()` -> `Mono<String>`, `.get(id).toRepresentation()` -> `Mono<UserRepresentation>`, `.get(id).resetPassword()`, `clients().findByClientId()`, `tokenResource().grantToken()` / `.refreshToken()` / `.clientCredentials()` / `.introspect()`.

**0.2.4+ APIs:** `realm().groupByPath(path)`, `groups().get(id).roles().realmLevel()` / `.clientLevel(uuid)`,
`realm().clientScopes()`, `clients().get(uuid).getDefaultClientScopes()` / `.addDefaultClientScope()`.

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
        keycloak:                  # shared block (0.2.4+ — was under sync-role)
          server-url: https://keycloak.example.com
          realm: master
          client-id: admin-cli
          client-secret: secret
          client-defaults:
            service-accounts-enabled: true
            public-client: false
            protocol: openid-connect
        sync-role:
          enabled: true            # only flag (0.2.4+) — keycloak config moved to parent
        group-role-authorization:  # 0.2.4+ — alternative to resource_access claim
          enabled: false
```

## Version Notes

- **0.2.1:** `summer-security-core` renamed to `summer-jwt-resource-server`; new `summer-apikey-resource-server` module; `ReactiveApisixCustomizer` now takes `ObjectMapper` constructor param; `SecurityErrorResponseWriter` added
- **0.2.3:** `sync-role.enable` renamed to `sync-role.enabled`; `matchIfMissing=true` — activates when `server-url` non-blank; `hasText()` check prevents empty server-url from triggering sync; `RoleDefinitionScanner` registered as Spring bean; `KeycloakException` expanded from ~5 to ~58 error mappings
- **0.2.4:** Keycloak config moved from `sync-role` to shared `keycloak` block (BREAKING);
  `UserInfoAuthenticationConverter` now returns `Mono` (BREAKING); group-role authorization added; new Keycloak APIs:
  group-by-path, group role-mappings, client scopes, client default/optional scopes;
  `ReactiveGroupRoleAutoConfiguration` added

See `references/keycloak-error-map.md` for the full KeycloakException error mapping table and Keycloak resource API.
