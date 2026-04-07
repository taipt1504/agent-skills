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

**7 mandatory actions** — EVERY resource MUST define all 7:

| Action | Constant Suffix | Description |
|--------|----------------|-------------|
| `view` | `_VIEW` | Xem danh sách / chi tiết |
| `create` | `_CREATE` | Tạo mới |
| `update` | `_UPDATE` | Cập nhật |
| `delete` | `_DELETE` | Xóa |
| `approve` | `_APPROVE` | Phê duyệt |
| `import` | `_IMPORT` | Nhập dữ liệu |
| `export` | `_EXPORT` | Xuất dữ liệu |

**FeatureDef / ResourceDef `name`** — ALWAYS Vietnamese. The `code` stays in English kebab-case.

```java
@AuthRoles(resources = {
    @ResourceDef(code = "my-svc", name = "Dịch vụ của tôi",
        attributes = @AttributeDef(key = "tier", value = "premium"),
        features = {
            @FeatureDef(code = "user-mgmt", name = "Quản lý người dùng"),
            @FeatureDef(code = "order-mgmt", name = "Quản lý đơn hàng")
        })
})
@Component
public class Roles {
    // user-mgmt: all 7 actions
    public static final String USER_VIEW    = "my-svc:user:view";
    public static final String USER_CREATE  = "my-svc:user:create";
    public static final String USER_UPDATE  = "my-svc:user:update";
    public static final String USER_DELETE  = "my-svc:user:delete";
    public static final String USER_APPROVE = "my-svc:user:approve";
    public static final String USER_IMPORT  = "my-svc:user:import";
    public static final String USER_EXPORT  = "my-svc:user:export";

    // order-mgmt: all 7 actions
    public static final String ORDER_VIEW    = "my-svc:order:view";
    public static final String ORDER_CREATE  = "my-svc:order:create";
    public static final String ORDER_UPDATE  = "my-svc:order:update";
    public static final String ORDER_DELETE  = "my-svc:order:delete";
    public static final String ORDER_APPROVE = "my-svc:order:approve";
    public static final String ORDER_IMPORT  = "my-svc:order:import";
    public static final String ORDER_EXPORT  = "my-svc:order:export";
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
- Always define ALL 7 actions (view, create, update, delete, approve, import, export) for every resource — incomplete role sets break permission UIs and audits.
- Always use Vietnamese for `@ResourceDef(name)` and `@FeatureDef(name)` — `code` stays English kebab-case.
- Always use `@PreAuthorize("hasAnyRole(@roles.XXX)")` for endpoint authorization — never rely solely on path matchers.
- Never expose Keycloak client secrets in application.yml — use environment variables or Vault.
- Always check Summer version before using group-role authorization — requires 0.2.4+.

## Related Skills

- **summer-core** — Shared types (Member, CallerAware) decoded from X-Userinfo
- **summer-test** — Mock X-Userinfo header for testing @AuthRoles-protected endpoints
- **spring-security** — General Spring Security patterns, JWT, CORS
- **summer-rest** — BaseController + RequestHandler secured by @PreAuthorize
