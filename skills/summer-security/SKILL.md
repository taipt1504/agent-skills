---
name: summer-security
description: Summer Framework security — APISIX auth integration with X-Userinfo header, multi-realm provider config (0.3.0+), @AuthRoles annotation for role definitions, SecurityWebFilterChain config, ReactiveKeycloakClient for Keycloak resource API, KeycloakRoleSynchronizer, KeycloakException error mapping, JWT blacklist via Redis (0.3.0+), and group-role authorization with layered cache (0.2.4+).
triggers:
  natural: ["auth roles", "keycloak client", "summer security", "multi realm", "jwt blacklist", "group role authorization"]
  code: ["@AuthRoles", "ReactiveKeycloakClient", "f8a.security", "MultiRealmAuthenticationConverter", "GroupRoleResolver", "GroupRoleInvalidator", "JwtBlacklistChecker"]
requires: ["summer-core", "spring-security"]
---

# Summer Security — APISIX, Keycloak & Roles

**Gate:** Verify summer-core is loaded and `io.f8a.summer:summer-platform` is in build.gradle before proceeding.

**Modules:** `summer-security-autoconfigure` | `summer-keycloak` | `summer-apisix-resource-server` | `summer-jwt-resource-server` | `summer-apikey-resource-server`

**This SKILL.md tracks the LATEST stable schema (0.3.4).** For older versions load the matching
overlay from [references/versions/](references/versions/). 0.3.5 made no security changes.

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

    // order-mgmt: all 7 actions (use the same pattern)
}
```

Annotations (in `summer-core`): `@AuthRoles` (resources), `@ResourceDef` (code, name, description, attributes, features), `@AttributeDef` (key, value), `@FeatureDef` (code, name, description).

## Configuration — Multi-realm (0.3.x canon)

```yaml
f8a:
  security:
    apisix:
      resource-server:
        enabled: true
        role-hierarchy: "ROLE_ADMIN > ROLE_USER"
        blacklist-prefix-key: "auth-blacklist"          # 0.3.0+: enable JWT blacklist
        sync-role: backoffice                           # 0.3.2+: provider id, not boolean
        providers:
          backoffice:                                   # provider id = scopeKey for caches
            server-url: ${KC_INTERNAL_URL}              # Admin API base URL
            realm: ewallet_backoffice
            # issuer-uri: <override>                    # 0.3.3+: optional, defaults to serverUrl + "/realms/" + realm
            client-id: ${KC_CLIENT_ID}
            client-secret: ${KC_CLIENT_SECRET}
            group-role-authorization: true              # 0.3.2+: per-provider opt-in
          partner:
            server-url: https://kc.partner.com
            realm: tenant1
            # No client-id/secret needed — partner only does inbound auth, no admin calls
        group-role-authorization:                       # global cache config (0.3.2+)
          claim-name: role_groups
          l1:
            ttl: 60s
          l2:                                           # omit entire block = L1-only
            ttl: 5m
            invalidation-channel: "group-role-changes"
            key-prefix: "auth-group-role:"
```

### Provider rules (0.3.x)

- `providers.<id>` is the only place to declare an issuer. The map key (e.g. `backoffice`) becomes
  the **scope key** used by group-role caches and invalidation payloads.
- `serverUrl + "/realms/" + realm` computes the JWT issuer the resource server expects in the
  `iss` claim. Set `issuer-uri` (0.3.3+) when the public token issuer differs from the Admin API
  hostname (reverse proxy, internal/external split).
- Admin credentials (`client-id` + `client-secret`) are required only when the provider is the
  `sync-role` target **or** has `group-role-authorization: true`. Pure inbound-auth providers
  (token decoding only) skip them.
- Startup fails fast (`IllegalStateException`) if any of those guarantees is violated.

## JWT Blacklist (0.3.0+)

Enable revocation by setting `blacklist-prefix-key`. Each authenticated request runs
`EXISTS <prefix>:<jti>` against Redis; presence → 401. Fail-open on Redis error.

```yaml
f8a.security.apisix.resource-server:
  blacklist-prefix-key: "auth-blacklist"
```

Publish a revocation:

```
SET auth-blacklist:<jti> 1 EX <remaining-token-seconds>
```

Override the default Redis check by providing your own `JwtBlacklistChecker` bean
(`@ConditionalOnMissingBean`) — useful for DB-backed lists, composite checks, or in-memory tests.

## Group-Role Authorization (0.2.4+, scoped per provider since 0.3.2+)

Alternative to the default `resource_access` JWT claim. Resolves roles from group membership via
a layered cache: **L1 Caffeine (per-instance) → L2 Redis Sets (shared) → L3 Keycloak Admin API**.
Each scope (provider) owns its own resolver and its own L2 key namespace
(`<keyPrefix><scopeKey>:<groupName>`), so multiple realms safely share one Redis instance.

### Key classes

| Class | Module | Purpose |
|---|---|---|
| `GroupRoleAuthenticationConverter` | apisix-resource-server | Reads `role_groups` claim → delegates to resolver |
| `GroupRoleResolver` | apisix-resource-server | L1 → L2 → L3 cascade. One per provider; carries `scopeKey` (0.3.2+) |
| `GroupRoleFetcher` | apisix-resource-server | `@FunctionalInterface` for L3 source of truth |
| `GroupRoleInvalidator` | apisix-resource-server | Publishes `<scope>:<group>` invalidation messages |
| `MultiRealmAuthenticationConverter` | apisix-resource-server | Routes tokens by `iss` claim to per-provider converters (0.3.2+) |
| `ReactiveApisixKeycloakAdminAutoConfiguration` | security-autoconfigure | Wires per-provider resolvers, invalidator, pub/sub listener |

### Invalidating the cache

`GroupRoleInvalidator` exposes both **targeted** (per-scope) and **broadcast** forms:

```java
// Targeted (preferred when caller knows the provider).
groupRoleInvalidator.invalidate("backoffice", "/admins").subscribe();

// Broadcast — clears "/admins" across every provider's cache. (0.3.3+)
groupRoleInvalidator.invalidate("/admins").subscribe();
```

Behind the scenes the broadcast overload publishes payload `*:<group>`; the targeted form
publishes `<scope>:<group>`. Both ride the same Redis channel
(`f8a...resource-server.group-role-authorization.l2.invalidation-channel`).

When `scopeKey` doesn't match any registered resolver, the listener logs at DEBUG and drops the
message. Use the wildcard form when the publisher can't (or shouldn't) map realm → provider id.

## Server-Sent Events Auth (0.3.4+)

Browsers' `EventSource` API can't send custom headers, so SSE endpoints authenticate via `?token=<jwt>` in the URL. Summer 0.3.4 ships `SseQueryParamTokenFilter` — services that had drifted copies under `config/sse/` should **delete the local copy** and declare an `SseAuthCustomizer` bean.

### Wiring

Auto-configured as a `WebFilter` bean by `ReactiveApisixResourceServerAutoConfiguration` at order `-100` (runs before the APISIX `AuthenticationWebFilter`). With **no** `SseAuthCustomizer` bean, the filter has zero rules and is a no-op — services opt in by registering a customizer.

```java
@Bean
SseAuthCustomizer sseRoutes() {
  return reg -> reg
      .pathStartsWith("/api/v1/public/sse/admin/", "bo")        // only 'bo' tokens
      .pathStartsWith("/api/v1/public/sse/",       "end-user")  // only 'end-user' tokens
      .acceptEventStream("end-user");                            // any other SSE → end-user
}
```

Rules are tested in registration order; first match wins. If no rule matches, the request bypasses the SSE filter and downstream auth still runs.

### Routing model — by provider key, not by `iss`

Rules carry a **provider key** (one of `f8a.security.apisix.resource-server.providers.<id>`), not an issuer URL. The auto-config builds the `ReactiveJwtDecoder` against that provider's `issuerUri()`; the decoder enforces `iss` natively, so a token issued by a **different** registered provider can never authenticate on a path bound to another provider.

### Fail-fast at startup

- Customizer rule references a provider id not in `providers.<id>` → `IllegalStateException` listing the known ids. Catches typos before they 401 every SSE request silently.
- `SseQueryParamTokenFilter.MatchRule` constructor rejects `null`/blank `providerId` and `null` `matcher`.

### Public API

| Type | Package |
|---|---|
| `SseQueryParamTokenFilter` | `io.f8a.summer.security.apisix.server.resource.web.server.filter` |
| `SseQueryParamTokenFilter.MatchRule` | nested record `(Predicate<ServerWebExchange> matcher, String providerId)` |
| `SseAuthCustomizer` | `io.f8a.summer.autoconfigure.security.apisix.resource.reactive` (functional, single `customize`) |
| `SseAuthCustomizer.Registration` | inner class with `matcher`, `pathStartsWith`, `pathContains`, `acceptEventStream` builders |

### Per-request flow

```
SSE request → first matching rule → providerId
            → decoderResolver.apply(providerId)
            → decoder.decode(token)            // verifies signature + iss
            → MultiRealmAuthenticationConverter.convert(oidcIdToken)
            → ReactiveSecurityContextHolder.withAuthentication(auth)
            → continue chain
```

The filter reuses the existing `MultiRealmAuthenticationConverter`, so the post-decode role/userinfo mapping is identical to non-SSE routes.

### Keep `permitAll()` on SSE paths

```java
.pathMatchers(HttpMethod.GET, "/api/v1/public/sse/**").permitAll()
```

The SSE filter populates the security context before the APISIX filter ever sees the request, but `permitAll()` is what lets the request through `authorizeExchange()` for token-based auth via the SSE path.

## `ProviderJwtDecoderResolver` (0.3.4+)

`Function<String, ReactiveJwtDecoder>` extracted from the SSE auto-config so anything that needs `provider key → ReactiveJwtDecoder` can inject it.

**Package:** `io.f8a.summer.security.apisix.server.resource.authentication.ProviderJwtDecoderResolver`

- Decoders are built **lazily** on first lookup via `ReactiveJwtDecoders.fromIssuerLocation(provider.issuerUri())` (synchronous HTTP fetch of `.well-known/openid-configuration`). Lazy-init means an unreachable OIDC server doesn't block app startup.
- Cached in a `ConcurrentHashMap` keyed by provider id.
- Returns `null` when the provider id is not in the map. Callers should treat null as a misconfiguration — auto-config validates rule provider ids at startup, so production hits are unexpected.

Override by declaring your own `ProviderJwtDecoderResolver` bean (e.g. for tests with a static decoder map). Auto-configured by `ReactiveApisixResourceServerAutoConfiguration` with `@ConditionalOnMissingBean`.

## `KeycloakRoleSynchronizer` — no more null bean (0.3.4+)

Previously the bean method returned `null` when `sync-role` wasn't configured, registering a `NullBean` placeholder in the application context. `@Autowired KeycloakRoleSynchronizer` (required) blew up with NPE-flavoured errors later.

**Now:** the bean is conditionally created via `@ConditionalOnExpression("!'${f8a.security.apisix.resource-server.sync-role:}'.trim().isEmpty()")` — when `sync-role` is unset the bean is **not registered at all**. Plus `@ConditionalOnMissingBean` so consumers can override.

- `@Autowired(required = false)` / `ObjectProvider<KeycloakRoleSynchronizer>` — same observable behaviour (null when unsatisfied).
- `@Autowired` (required, sync disabled) — was: `NullBean` injected → NPE later. Now: clean `NoSuchBeanDefinitionException` at startup.

The `"sync-role not configured — role synchronization disabled"` info log is gone. Absence of `"Role synchronization will run against provider..."` at startup is now the signal that sync is off.

## ReactiveKeycloakClient

Resource-based API mirroring keycloak-admin-client SPI. Auto-configured per provider that has
admin credentials.

```java
var config = new KeycloakConfig();
config.setServerUrl("https://keycloak.example.com");
config.setRealm("my-realm");
config.setClientId("admin-cli");
config.setClientSecret("secret");
var keycloak = new ReactiveKeycloakClient(config);
```

**Navigation:** `keycloak.users()` / `.clients()` / `.groups()` / `.realm()` / `.tokenResource()` / `.tokenProvider()`

For complete `ReactiveKeycloakClient` API, see [references/keycloak-error-map.md](references/keycloak-error-map.md).

## KeycloakRoleSynchronizer

`ApplicationRunner` at startup. Scans `@AuthRoles` → syncs clients, roles, features (JSON
attribute), custom attributes to Keycloak. Runs against the provider named by top-level
`sync-role: <provider-id>` (0.3.2+).

## Version Notes

Headline only — for full per-version detail load the matching overlay:

- **0.3.4** (2026-05-08) — `SseQueryParamTokenFilter` + `SseAuthCustomizer` (delete service-local SSE filters); `ProviderJwtDecoderResolver` reusable bean; `KeycloakRoleSynchronizer` no longer a null bean. See [versions/0.3.4.md](references/versions/0.3.4.md).
- **0.3.3** (2026-05-07) — optional `provider.issuer-uri`; broadcast `GroupRoleInvalidator.invalidate(groupName)` + `BROADCAST_SCOPE = "*"`. See [versions/0.3.3.md](references/versions/0.3.3.md).
- **0.3.2** — multi-realm via `providers.<id>` (BREAKING vs 0.3.0); `MultiRealmAuthenticationConverter`; `sync-role` is now a top-level provider-id pointer; group-role cache scoped by provider id. See [versions/0.3.2.md](references/versions/0.3.2.md).
- **0.3.0** — JWT blacklist via Redis (`blacklist-prefix-key`); `JwtBlacklistChecker` strategy interface; `ApisixAuthenticationManager` 3-arg constructor (BREAKING for direct instantiation). See [versions/0.3.0.md](references/versions/0.3.0.md).
- **0.2.4** — Keycloak config moved to shared `keycloak` block (BREAKING); `UserInfoAuthenticationConverter` returns `Mono` (BREAKING); group-role authorization added. See [versions/0.2.4.md](references/versions/0.2.4.md).
- **0.2.3** — `KeycloakException` ~50 mappings; `sync-role.enable` → `sync-role.enabled`. See [versions/0.2.3.md](references/versions/0.2.3.md).
- **0.2.1** — `summer-security-core` → `summer-jwt-resource-server` (BREAKING module rename); new `summer-apikey-resource-server`. See [versions/0.2.1.md](references/versions/0.2.1.md).

For the full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Rules

- Always use `summerCustomizer.customize(http)` + `apisixCustomizer.customize(http)` in `SecurityWebFilterChain` — never hand-roll CORS/CSRF/session for Summer projects.
- Always define roles via `@AuthRoles` + `@ResourceDef`; never hardcode role strings outside the `Roles` class.
- Always define ALL 7 actions (view, create, update, delete, approve, import, export) for every resource — incomplete sets break permission UIs and audits.
- Always use Vietnamese for `@ResourceDef(name)` and `@FeatureDef(name)`. `code` stays English kebab-case.
- Always use `@PreAuthorize("hasAnyRole(@roles.XXX)")` for endpoint authorization — path matchers alone are not enough.
- Never expose Keycloak client secrets in `application.yml` — use environment variables or Vault.
- Always check Summer version before suggesting features (group-role: 0.2.4+; multi-realm `providers.*`: 0.3.0+; JWT blacklist: 0.3.0+; broadcast invalidator: 0.3.3+; SSE filter + `ProviderJwtDecoderResolver`: 0.3.4+).
- For 0.3.4+ services with SSE endpoints, **never** ship a service-local `SseQueryParamTokenFilter` — register a `SseAuthCustomizer` bean against Summer's auto-wired filter. A duplicate `@Component` either collides or silently shadows the Summer one.
- For 0.3.0+ projects, never write the legacy single-`keycloak.*` block — that schema is removed. Use `providers.<id>:` always.
- Multi-realm projects: assign each provider a stable `id` and reuse it as the `scopeKey` for invalidation calls — never invent ad-hoc scope strings.

## References

- **[references/keycloak-error-map.md](references/keycloak-error-map.md)** — Full `KeycloakException` mapping table and Keycloak resource API.
- **[references/versions/](references/versions/)** — Per-version notes (0.2.1 → 0.3.3).

## Related Skills

- **summer-core** — Shared types (`Member`, `CallerAware`) decoded from `X-Userinfo`; version detection.
- **summer-test** — Mock `X-Userinfo` header for testing `@AuthRoles`-protected endpoints.
- **spring-security** — General Spring Security patterns, JWT, CORS.
- **summer-rest** — `BaseController` + `RequestHandler` secured by `@PreAuthorize`.
