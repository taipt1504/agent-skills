---
name: summer-security
description: Summer Framework security — APISIX auth integration with X-Userinfo header, multi-realm provider config (0.3.0+), @AuthRoles annotation for role definitions, SecurityWebFilterChain config, ReactiveKeycloakClient for Keycloak resource API, KeycloakRoleSynchronizer, KeycloakException error mapping, JWT blacklist via Redis (0.3.0+), and group-role authorization with layered cache (0.2.4+).
triggers:
  natural: ["auth roles", "keycloak client", "summer security", "multi realm", "jwt blacklist", "group role authorization"]
  code: ["@AuthRoles", "ReactiveKeycloakClient", "f8a.security", "MultiRealmAuthenticationConverter", "GroupRoleResolver", "GroupRoleInvalidator", "JwtBlacklistChecker"]
requires: ["summer-core", "spring-security"]
applicability:
  always: false
  triggers:
    files_match: ["**/*SecurityConfig*.java", "**/*AuthRoles*.java"]
    code_patterns: ["io.f8a.summer.security", "@AuthRoles", "ReactiveKeycloakClient", "f8a.security", "CallerAware", "RequestContextService"]
    task_keywords: ["summer security", "auth roles", "Keycloak", "APISIX", "caller context", "audit context"]
    related_skills: ["spring-security"]
    related_rules:
      - rules/common/security.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 90%+: @AuthRoles change OR Keycloak integration OR caller-context wiring
  HIGH 80%+: new secured Summer endpoint
  MEDIUM 40-79%: audit context propagation refactor
  LOW 1-39%: caller of secured Summer method
  ZERO: project lacks io.f8a.summer:summer-security
---

# Summer Security — APISIX, Keycloak & Roles

**Gate:** Verify summer-core loaded and `io.f8a.summer:summer-platform` in build.gradle.

**Modules:** `summer-security-autoconfigure` | `summer-keycloak` | `summer-apisix-resource-server` | `summer-jwt-resource-server` | `summer-apikey-resource-server`

**Tracks LATEST stable schema (0.3.4).** Older versions: load matching overlay from [references/versions/](references/versions/). 0.3.5: no security changes.

## APISIX Auth Integration

APISIX gateway validates JWT, forwards `X-Userinfo` header (Base64 JSON) decoded into `Member`.

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

**FeatureDef / ResourceDef `name`** — ALWAYS Vietnamese. `code` stays English kebab-case.

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

Annotations (`summer-core`): `@AuthRoles` (resources), `@ResourceDef` (code, name, description, attributes, features), `@AttributeDef` (key, value), `@FeatureDef` (code, name, description).

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

- `providers.<id>` declares issuer. Map key (e.g. `backoffice`) becomes **scope key** for group-role caches and invalidation payloads.
- `serverUrl + "/realms/" + realm` computes JWT `iss` claim. Set `issuer-uri` (0.3.3+) when public token issuer differs from Admin API hostname (reverse proxy, internal/external split).
- Admin credentials (`client-id` + `client-secret`) required only when provider is `sync-role` target **or** has `group-role-authorization: true`. Pure inbound-auth providers skip them.
- Startup fails fast (`IllegalStateException`) on violations.

## JWT Blacklist (0.3.0+)

Enable revocation by setting `blacklist-prefix-key`. Each request runs `EXISTS <prefix>:<jti>` against Redis; presence → 401. Fail-open on Redis error.

```yaml
f8a.security.apisix.resource-server:
  blacklist-prefix-key: "auth-blacklist"
```

Publish a revocation:

```
SET auth-blacklist:<jti> 1 EX <remaining-token-seconds>
```

Override by providing your own `JwtBlacklistChecker` bean (`@ConditionalOnMissingBean`) — for DB-backed lists, composite checks, or in-memory tests.

## Group-Role Authorization (0.2.4+, scoped per provider since 0.3.2+)

Alternative to `resource_access` JWT claim. Resolves roles from group membership via layered cache: **L1 Caffeine (per-instance) → L2 Redis Sets (shared) → L3 Keycloak Admin API**. Each scope (provider) owns its own resolver and L2 key namespace (`<keyPrefix><scopeKey>:<groupName>`), so multiple realms share one Redis instance safely.

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

Broadcast publishes `*:<group>`; targeted publishes `<scope>:<group>`. Both ride same Redis channel (`f8a...resource-server.group-role-authorization.l2.invalidation-channel`).

Unmatched `scopeKey` → DEBUG log, message dropped. Use wildcard when publisher can't map realm → provider id.

## Server-Sent Events Auth (0.3.4+)

Browsers' `EventSource` can't send custom headers, so SSE endpoints authenticate via `?token=<jwt>`. Summer 0.3.4 ships `SseQueryParamTokenFilter` — delete any service-local copy under `config/sse/` and declare an `SseAuthCustomizer` bean.

### Wiring

Auto-configured as `WebFilter` by `ReactiveApisixResourceServerAutoConfiguration` at order `-100` (before APISIX `AuthenticationWebFilter`). No `SseAuthCustomizer` bean → zero rules, no-op. Services opt in by registering a customizer.

```java
@Bean
SseAuthCustomizer sseRoutes() {
  return reg -> reg
      .pathStartsWith("/api/v1/public/sse/admin/", "bo")        // only 'bo' tokens
      .pathStartsWith("/api/v1/public/sse/",       "end-user")  // only 'end-user' tokens
      .acceptEventStream("end-user");                            // any other SSE → end-user
}
```

Rules tested in registration order; first match wins. No match → request bypasses SSE filter, downstream auth still runs.

### Routing model — by provider key, not by `iss`

Rules carry a **provider key** (`f8a.security.apisix.resource-server.providers.<id>`), not an issuer URL. Auto-config builds `ReactiveJwtDecoder` against that provider's `issuerUri()`; decoder enforces `iss` natively — token from different provider never authenticates on another provider's path.

### Fail-fast at startup

- Rule references unknown provider id → `IllegalStateException` listing known ids. Catches typos before silent 401s.
- `SseQueryParamTokenFilter.MatchRule` rejects `null`/blank `providerId` and `null` `matcher`.

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

Filter reuses `MultiRealmAuthenticationConverter` — post-decode role/userinfo mapping identical to non-SSE routes.

### Keep `permitAll()` on SSE paths

```java
.pathMatchers(HttpMethod.GET, "/api/v1/public/sse/**").permitAll()
```

SSE filter populates security context before APISIX filter, but `permitAll()` lets request through `authorizeExchange()` for token-based auth via SSE path.

## `ProviderJwtDecoderResolver` (0.3.4+)

`Function<String, ReactiveJwtDecoder>` extracted from SSE auto-config for reuse by anything needing `provider key → ReactiveJwtDecoder`.

**Package:** `io.f8a.summer.security.apisix.server.resource.authentication.ProviderJwtDecoderResolver`

- Decoders built **lazily** on first lookup via `ReactiveJwtDecoders.fromIssuerLocation(provider.issuerUri())`. Lazy-init: unreachable OIDC server doesn't block startup.
- Cached in `ConcurrentHashMap` keyed by provider id.
- Returns `null` for unknown provider id — treat as misconfiguration; auto-config validates at startup so production hits are unexpected.

Override by declaring your own `ProviderJwtDecoderResolver` bean (e.g. static decoder map for tests). Auto-configured with `@ConditionalOnMissingBean`.

## `KeycloakRoleSynchronizer` — no more null bean (0.3.4+)

Previously returned `null` when `sync-role` unset, registering `NullBean`. `@Autowired KeycloakRoleSynchronizer` blew up with NPE-flavoured errors later.

**Now:** conditionally created via `@ConditionalOnExpression("!'${f8a.security.apisix.resource-server.sync-role:}'.trim().isEmpty()")` — unset `sync-role` → bean **not registered**. Plus `@ConditionalOnMissingBean` for override.

- `@Autowired(required = false)` / `ObjectProvider<KeycloakRoleSynchronizer>` — same observable behaviour.
- `@Autowired` (required, sync disabled) — was: `NullBean` → NPE. Now: clean `NoSuchBeanDefinitionException` at startup.

`"sync-role not configured"` log gone. Absence of `"Role synchronization will run against provider..."` signals sync off.

## ReactiveKeycloakClient

Resource-based API mirroring keycloak-admin-client SPI. Auto-configured per provider with admin credentials.

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

`ApplicationRunner` at startup. Scans `@AuthRoles` → syncs clients, roles, features (JSON attribute), custom attributes to Keycloak. Runs against provider named by `sync-role: <provider-id>` (0.3.2+).

## Version Notes

Headline only — full detail: load matching overlay:

- **0.3.4** — `SseQueryParamTokenFilter` + `SseAuthCustomizer`; `ProviderJwtDecoderResolver` bean; `KeycloakRoleSynchronizer` no longer null bean. [→](references/versions/0.3.4.md)
- **0.3.3** — optional `provider.issuer-uri`; broadcast `GroupRoleInvalidator.invalidate(groupName)` + `BROADCAST_SCOPE="*"`. [→](references/versions/0.3.3.md)
- **0.3.2** — multi-realm `providers.<id>` (BREAKING); `MultiRealmAuthenticationConverter`; `sync-role` top-level provider-id; group-role cache per provider. [→](references/versions/0.3.2.md)
- **0.3.0** — JWT blacklist (`blacklist-prefix-key`); `JwtBlacklistChecker`; `ApisixAuthenticationManager` 3-arg ctor (BREAKING). [→](references/versions/0.3.0.md)
- **0.2.4** — Keycloak config → shared `keycloak` block (BREAKING); `UserInfoAuthenticationConverter` → `Mono` (BREAKING); group-role auth added. [→](references/versions/0.2.4.md)
- **0.2.3** — `KeycloakException` ~50 mappings; `sync-role.enable` → `sync-role.enabled`. [→](references/versions/0.2.3.md)
- **0.2.1** — `summer-security-core` → `summer-jwt-resource-server` (BREAKING); `summer-apikey-resource-server` added. [→](references/versions/0.2.1.md)

For the full feature × version table see [`summer-core/references/version-matrix.md`](../summer-core/references/version-matrix.md).

## Rules

- Use `summerCustomizer.customize(http)` + `apisixCustomizer.customize(http)` in `SecurityWebFilterChain` — never hand-roll CORS/CSRF/session.
- Define roles via `@AuthRoles` + `@ResourceDef`; never hardcode role strings outside `Roles` class.
- Define ALL 7 actions (view, create, update, delete, approve, import, export) per resource — incomplete sets break permission UIs and audits.
- Vietnamese for `@ResourceDef(name)` and `@FeatureDef(name)`. `code` stays English kebab-case.
- Use `@PreAuthorize("hasAnyRole(@roles.XXX)")` — path matchers alone insufficient.
- Never expose Keycloak secrets in `application.yml` — use env vars or Vault.
- Check Summer version before suggesting features (group-role: 0.2.4+; multi-realm `providers.*`: 0.3.0+; JWT blacklist: 0.3.0+; broadcast invalidator: 0.3.3+; SSE filter + `ProviderJwtDecoderResolver`: 0.3.4+).
- 0.3.4+ SSE: never ship service-local `SseQueryParamTokenFilter` — register `SseAuthCustomizer` bean. Duplicate `@Component` collides or shadows silently.
- 0.3.0+: never write legacy `keycloak.*` block — removed. Use `providers.<id>:` always.
- Multi-realm: assign each provider stable `id`, reuse as `scopeKey` for invalidation — never invent ad-hoc scope strings.

## References

- **[references/keycloak-error-map.md](references/keycloak-error-map.md)** — `KeycloakException` mapping table and Keycloak resource API.
- **[references/versions/](references/versions/)** — Per-version notes (0.2.1 → 0.3.3).

## Related Skills

- **summer-core** — Shared types (`Member`, `CallerAware`) from `X-Userinfo`; version detection.
- **summer-test** — Mock `X-Userinfo` for testing `@AuthRoles`-protected endpoints.
- **spring-security** — Spring Security patterns, JWT, CORS.
- **summer-rest** — `BaseController` + `RequestHandler` secured by `@PreAuthorize`.
