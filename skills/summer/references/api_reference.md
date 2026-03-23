# Summer Framework — Full API Reference

## Table of Contents

1. [Configuration Properties](#configuration-properties)
2. [DDL Scripts](#ddl-scripts)
3. [Handler Pattern Details](#handler-pattern-details)
4. [Auto-Configuration Classes](#auto-configuration-classes)
5. [Domain Types](#domain-types)
6. [Keycloak Client API](#keycloak-client-api)

---

## Configuration Properties

### `f8a.common` (REST Auto-Configuration)

```yaml
f8a:
  common:
    enabled: true
    jackson:
      enabled: true
      fail-on-unknown-properties: false
      write-dates-as-timestamps: false
      include-null-values: false
      write-enums-using-to-string: true
      property-naming-strategy: LOWER_CAMEL_CASE
      date-format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
      time-zone: UTC
    logging:
      enabled: true
      aop:
        enabled: false
        log-headers: false
        log-request-body: false
        log-response-body: false
    exception-handling:
      enabled: true
    webclient:
      enabled: true
      max-connections: 100
      connect-timeout: 10s
      read-timeout: 30s
      max-idle-time: 30s
      max-life-time: 5m
      pending-acquire-timeout: 45s
      connection-pool-name: summer-pool
    actuator:
      enabled: true
    api-doc:
      enabled: false
      title: API Documentation
```

### `f8a.audit` (Audit Trail)

```yaml
f8a:
  audit:
    validate-on-startup: true  # AuditTableValidator checks audit_log schema on startup (default: true)
```

### `f8a.outbox` (Outbox Pattern)

```yaml
f8a:
  outbox:
    enabled: true
    validate-on-startup: true
    publisher:
      enabled: true
      batch-size: 100
    scheduler:
      publisher:
        cron: "*/5 * * * * *"
        initial-delay: 10s
      cleanup:
        cron: "0 0 2 * * ?"
        retention-days: 30
      failed-events:
        cron: "0 0 * * * ?"
        max-retry-threshold: 5
    circuit-breaker:
      enabled: true
      failure-rate-threshold: 50
      minimum-events: 10
      wait-duration-seconds: 60
      sliding-window-size: 100
```

### `f8a.security.apisix.resource-server`

```yaml
f8a:
  security:
    apisix:
      resource-server:
        enabled: true              # default true (matchIfMissing since 0.2.3)
        role-hierarchy: ""         # e.g. "ROLE_ADMIN > ROLE_USER"
        keycloak: # shared Keycloak connection (0.2.4+ — was under sync-role)
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
        group-role-authorization: # 0.2.4+ — alternative to resource_access claim
          enabled: false
          claim-name: role_groups
          l1:
            ttl: 60s
          l2: # omit = L1-only mode
            ttl: 5m
            invalidation-channel: "group-role-changes"
            key-prefix: "auth-group-role:"
            redis:
              host: localhost
              port: 6379
              password: ""
              database: 0
```

### `f8a.rate-limiter` (Rate Limiting)

```yaml
f8a:
  rate-limiter:
    key-prefix: "ratelimit:"            # global storage key prefix
    storage-type: redis                 # "redis" (default) or "memory"
    default-policy: # fallback for unmatched scopes
      strategy: token-bucket            # fixed-window, sliding-window, token-bucket
      limit: 100                        # max requests per window
      window: 60s                       # time window duration
      token-bucket-refill-rate: 0       # tokens/sec (0 = auto: limit/windowSec)
    policies: # named per-scope policies
      users:read:
        strategy: sliding-window
        limit: 1000
        window: 3600s
      orders:create:
        strategy: fixed-window
        limit: 10
        window: 60s
      auth:otp:
        strategy: fixed-window
        limit: 5
        window: 300s
```

---

## DDL Scripts

### audit_log

```sql
CREATE TABLE IF NOT EXISTS audit_log
(
    id                UUID PRIMARY KEY                  DEFAULT gen_random_uuid(),
    action            VARCHAR(50),
    intent            VARCHAR(50)              NOT NULL,
    actor_id          VARCHAR(100),
    actor_username    VARCHAR(100),
    actor_family_name VARCHAR(255),
    actor_given_name  VARCHAR(255),
    actor_email       VARCHAR(100),
    actor_roles       TEXT,
    request_id        VARCHAR(50),
    trace_id          VARCHAR(50),
    ip_address        VARCHAR(45),
    user_agent        TEXT,
    request_method    VARCHAR(10),
    request_uri       TEXT,
    entity_type       VARCHAR(255),
    entity_id         VARCHAR(100),
    comment           TEXT,
    old_values        JSONB,
    new_values        JSONB,
    diff_values       JSONB,
    timestamp         TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log (entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_intent ON audit_log (intent, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log (action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_trace ON audit_log (trace_id) WHERE trace_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity_intent ON audit_log (entity_type, intent, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity_action ON audit_log (entity_type, action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_old_values ON audit_log USING GIN (old_values);
CREATE INDEX IF NOT EXISTS idx_audit_log_new_values ON audit_log USING GIN (new_values);

-- Immutability trigger (prevents UPDATE and DELETE)
CREATE OR REPLACE FUNCTION prevent_audit_log_modification()
    RETURNS TRIGGER AS
$$
BEGIN
    IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'Audit logs cannot be updated'; END IF;
    IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Audit logs cannot be deleted'; END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

### outbox_events

```sql
CREATE TABLE outbox_events
(
    id            UUID PRIMARY KEY,
    aggregate_id  VARCHAR(255) NOT NULL,
    event_type    VARCHAR(255) NOT NULL,
    payload       JSONB        NOT NULL,
    published     BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    published_at  TIMESTAMPTZ,
    retry_count   INTEGER      NOT NULL DEFAULT 0,
    error_message TEXT
);
CREATE INDEX idx_outbox_unpublished ON outbox_events (published, created_at)
    WHERE published = FALSE;
```

---

## Handler Pattern Details

### Registration Flow

1. `Registry` scans all `@Handler` beans at startup
2. Maps each handler's request type to the handler instance
3. `SpringBus.dispatch(request)` looks up handler by request class
4. `AbstractController.executeMono(request)` calls `SpringBus`

### Creating a New Endpoint

1. Define request DTO (with validation annotations)
2. Define response DTO
3. Create handler implementing the appropriate interface
4. Add controller method that calls `executeMono(request)` or `executeFlux(request)`

### Transactional Handlers

Use `@RestTransactional` on the handler class or method for reactive transactions.

---

## Auto-Configuration Classes

| Class                                           | Module                    | Trigger                                                        |
|-------------------------------------------------|---------------------------|----------------------------------------------------------------|
| `SummerRestAutoConfiguration`                   | rest-autoconfigure        | Always                                                         |
| `SummerActuatorAutoConfiguration`               | rest-autoconfigure        | `InfoContributor` present                                      |
| `SummerApiDocAutoConfiguration`                 | rest-autoconfigure        | `f8a.common.api-doc.enabled=true`                              |
| `JacksonAutoConfiguration`                      | rest-autoconfigure        | `f8a.common.jackson.enabled=true`                              |
| `SummerR2dbcAutoConfiguration`                  | data-autoconfigure        | `R2dbcCustomConversions` present                               |
| `SummerR2dbcAuditAutoConfiguration`             | data-audit-autoconfigure  | `R2dbcRepository` present                                      |
| `AuditTableValidator`                           | data-audit-autoconfigure  | `f8a.audit.validate-on-startup=true` (default)                 |
| `SummerR2dbcOutboxAutoConfiguration`            | data-outbox-autoconfigure | `R2dbcRepository` present                                      |
| `OutboxTableValidator`                          | data-outbox-autoconfigure | `f8a.outbox.validate-on-startup=true` (default)                |
| `ReactiveBaseResourceServerAutoConfiguration`   | security-autoconfigure    | Always (reactive + security)                                   |
| `ReactiveApisixResourceServerAutoConfiguration` | security-autoconfigure    | `apisix.resource-server.enabled=true`                          |
| `ReactiveApisixRoleSyncAutoConfiguration`       | security-autoconfigure    | `keycloak.server-url` non-blank + `sync-role.enabled` (0.2.4+) |
| `ReactiveGroupRoleAutoConfiguration`            | security-autoconfigure    | `group-role-authorization.enabled=true` (0.2.4+)               |
| `SummerRateLimitAutoConfiguration`              | ratelimit-autoconfigure   | Auto (ratelimit-autoconfigure on classpath)                    |

---

## Domain Types

### Password

Value object for passwords. Use `@ValidPassword` for validation.

```java

@ValidPassword
private Password password;
```

Stored as plain string in DB via R2DBC converter.

### PhoneNumber

Value object for phone numbers. Use `@ValidPhoneNumber` for validation.

```java

@ValidPhoneNumber
private PhoneNumber phone;
```

### Member

Authenticated user info extracted from security context:

```java
public class Member {
    String id;
    String username;
    String givenName;
    String familyName;
    String email;
    Collection<GrantedAuthority> authorities;
}
```

### CallerAware

Mixin interface for reactive controllers/services to retrieve the current authenticated user:

```java
public class MyService implements CallerAware {
    public Mono<String> doSomething() {
        return getCaller().map(Member::getId);
    }
}
```

---

## Keycloak Client API

### ReactiveKeycloakClient

Entry point — self-creates `WebClient` from `KeycloakConfig.serverUrl`. Uses `ReactiveBearerAuthFilter` +
`KeycloakTokenProvider` for admin token caching.

**Construction:**
```java
var config = new KeycloakConfig();
config.

setServerUrl("https://keycloak.example.com");
config.

setRealm("my-realm");
config.

setClientId("admin-cli");
config.

setClientSecret("secret");

var keycloak = new ReactiveKeycloakClient(config);
// or with custom token provider:
var keycloak = new ReactiveKeycloakClient(config, customTokenProvider);
```

**Navigation:**
```java
keycloak.realm()              // ReactiveRealmResource (default realm)
keycloak.

realm("other")      // ReactiveRealmResource (explicit realm)
keycloak.

users()              // shortcut for realm().users()
keycloak.

clients()            // shortcut for realm().clients()
keycloak.

tokenResource()      // ReactiveTokenResource (no bearer auth)
keycloak.

tokenProvider()      // KeycloakTokenProvider
```

### Resource Interfaces

**ReactiveRealmResource**
- `users()` → `ReactiveUsersResource`
- `clients()` → `ReactiveClientsResource`
- `groups()` → `ReactiveGroupsResource`
- `clientScopes()` → `ReactiveClientScopesResource` (0.2.4+)
- `groupByPath(String path)` → `Mono<GroupRepresentation>` (0.2.4+)

**ReactiveUsersResource**
| Method | Return | Description |
|---|---|---|
| `create(UserRepresentation)` | `Mono<String>` | Returns userId from Location header |
| `list(Integer first, Integer max)` | `Flux<UserRepresentation>` | Paginated list |
| `search(String username, Boolean exact)` | `Flux<UserRepresentation>` | Search by username |
| `count()` | `Mono<Integer>` | Total user count |
| `get(String id)` | `ReactiveUserResource` | Sub-resource for single user |

**ReactiveUserResource**
| Method | Return | Description |
|--------|--------|-------------|
| `toRepresentation()` | `Mono<UserRepresentation>` | Get user details |
| `update(UserRepresentation)` | `Mono<Void>` | Update user |
| `remove()` | `Mono<Void>` | Delete user |
| `resetPassword(CredentialRepresentation)` | `Mono<Void>` | Reset password |
| `logout()` | `Mono<Void>` | Logout all sessions |

**ReactiveClientsResource**
| Method | Return | Description |
|--------|--------|-------------|
| `create(ClientRepresentation)` | `Mono<String>` | Returns client UUID |
| `findAll()` | `Flux<ClientRepresentation>` | List all clients |
| `findByClientId(String)` | `Flux<ClientRepresentation>` | Search by clientId |
| `get(String id)` | `ReactiveClientResource` | Sub-resource for single client |

**ReactiveClientResource**
| Method | Return | Description |
|--------|--------|-------------|
| `toRepresentation()` | `Mono<ClientRepresentation>` | Get client details |
| `update(ClientRepresentation)` | `Mono<Void>` | Update client |
| `roles()` | `ReactiveRolesResource` | Client role management |
| `getDefaultClientScopes()` | `Flux<ClientScopeRepresentation>` | List default scopes (0.2.4+) |
| `addDefaultClientScope(String)` | `Mono<Void>` | Add default scope (0.2.4+) |
| `removeDefaultClientScope(String)` | `Mono<Void>` | Remove default scope (0.2.4+) |
| `getOptionalClientScopes()` | `Flux<ClientScopeRepresentation>` | List optional scopes (0.2.4+) |
| `addOptionalClientScope(String)` | `Mono<Void>` | Add optional scope (0.2.4+) |
| `removeOptionalClientScope(String)` | `Mono<Void>` | Remove optional scope (0.2.4+) |

**ReactiveRolesResource**
| Method | Return | Description |
|--------|--------|-------------|
| `list()` | `Flux<RoleRepresentation>` | List client roles |
| `create(RoleRepresentation)` | `Mono<Void>` | Create client role |

**ReactiveGroupResource** (0.2.4+: `roles()` added)
| Method | Return | Description |
|--------|--------|-------------|
| `toRepresentation()` | `Mono<GroupRepresentation>` | Get group details |
| `update(GroupRepresentation)` | `Mono<Void>` | Update group |
| `remove()` | `Mono<Void>` | Delete group |
| `members(Integer, Integer)` | `Flux<UserRepresentation>` | List group members |
| `roles()` | `ReactiveRoleMappingResource` | Group role mappings (0.2.4+) |

**ReactiveRoleMappingResource** (0.2.4+)
| Method | Return | Description |
|--------|--------|-------------|
| `realmLevel()` | `ReactiveRoleScopeResource` | Realm-level role mappings |
| `clientLevel(String)` | `ReactiveRoleScopeResource` | Client-level role mappings |

**ReactiveRoleScopeResource** (0.2.4+)
| Method | Return | Description |
|--------|--------|-------------|
| `listAll()` | `Flux<RoleRepresentation>` | All assigned roles |
| `listAvailable()` | `Flux<RoleRepresentation>` | Available (unassigned) roles |
| `listEffective()` | `Flux<RoleRepresentation>` | Effective (including composites) |
| `add(List<RoleRepresentation>)` | `Mono<Void>` | Assign roles |
| `remove(List<RoleRepresentation>)` | `Mono<Void>` | Unassign roles |

**ReactiveClientScopesResource** (0.2.4+)
| Method | Return | Description |
|--------|--------|-------------|
| `findAll()` | `Flux<ClientScopeRepresentation>` | List all client scopes |
| `create(ClientScopeRepresentation)` | `Mono<String>` | Create client scope |
| `get(String)` | `ReactiveClientScopeResource` | Sub-resource for single scope |

**ReactiveClientScopeResource** (0.2.4+)
| Method | Return | Description |
|--------|--------|-------------|
| `toRepresentation()` | `Mono<ClientScopeRepresentation>` | Get scope details |
| `update(ClientScopeRepresentation)` | `Mono<Void>` | Update scope |
| `remove()` | `Mono<Void>` | Delete scope |
| `protocolMappers()` | `ReactiveProtocolMappersResource` | Protocol mapper management |

**ReactiveTokenResource** (no admin auth — uses separate WebClient)
| Method | Return | Description |
|--------|--------|-------------|
| `grantToken(String user, String pass)` | `Mono<AccessTokenResponse>` | Password grant |
| `refreshToken(String refreshToken)` | `Mono<AccessTokenResponse>` | Refresh token |
| `clientCredentials(String clientId, String secret, String scope)` | `Mono<AccessTokenResponse>` | Client credentials |
| `introspect(String token)` | `Mono<Map<String,Object>>` | Token introspection |
| `userInfo(String accessToken)` | `Mono<Map<String,Object>>` | UserInfo endpoint |
| `logout(String refreshToken)` | `Mono<Void>` | Logout via refresh token |

### DTOs

Uses official Keycloak representations from `org.keycloak.representations.idm`:

- `UserRepresentation` — user CRUD
- `ClientRepresentation` — client CRUD
- `RoleRepresentation` — role management
- `CredentialRepresentation` — password reset
- `AccessTokenResponse` — token operations

### KeycloakException

Extends `ViewableException`. Comprehensive auto-mapping of Keycloak error responses (expanded to ~58 cases in **0.2.3+
**; pre-0.2.3 only ~5 mappings were present):

| Keycloak Error                                   | Code                                        | Status |
|--------------------------------------------------|---------------------------------------------|--------|
| `"Account disabled"`                             | `keycloak.account.disabled`                 | 400    |
| `"Invalid user credentials"`                     | `keycloak.authentication.failed`            | 401    |
| `"Account is not fully set up"`                  | `keycloak.account.not.setup`                | 400    |
| `"Session not active"`                           | `keycloak.session.inactive`                 | 401    |
| `"Token is not active"`                          | `keycloak.token.inactive`                   | 401    |
| `"Invalid username or password"`                 | `keycloak.authentication.failed`            | 401    |
| `"Invalid user"`                                 | `keycloak.user.invalid`                     | 401    |
| `"User not found"`                               | `keycloak.user.not.found`                   | 401    |
| `"User is disabled"`                             | `keycloak.user.disabled`                    | 403    |
| `"User is temporarily disabled"`                 | `keycloak.user.temporarily.disabled`        | 403    |
| `"User account is locked"`                       | `keycloak.user.locked`                      | 403    |
| `"User must verify email"`                       | `keycloak.user.email.verification.required` | 400    |
| `"User email not verified"`                      | `keycloak.user.email.not.verified`          | 400    |
| `"User must update password"`                    | `keycloak.user.password.update.required`    | 400    |
| `"User must configure OTP"`                      | `keycloak.user.otp.required`                | 400    |
| `"User must update profile"`                     | `keycloak.user.profile.update.required`     | 400    |
| `"Session expired"`                              | `keycloak.session.expired`                  | 401    |
| `"User session not found"`                       | `keycloak.session.not.found`                | 401    |
| `"Invalid session"`                              | `keycloak.session.invalid`                  | 401    |
| `"Invalid token"`                                | `keycloak.token.invalid`                    | 401    |
| `"Token signature invalid"`                      | `keycloak.token.signature.invalid`          | 401    |
| `"Token expired"`                                | `keycloak.token.expired`                    | 401    |
| `"Access token expired"`                         | `keycloak.token.access.expired`             | 401    |
| `"Refresh token expired"`                        | `keycloak.token.refresh.expired`            | 401    |
| `"Invalid refresh token"`                        | `keycloak.token.refresh.invalid`            | 401    |
| `"Refresh token reused"`                         | `keycloak.token.refresh.reused`             | 401    |
| `"Invalid bearer token"`                         | `keycloak.token.bearer.invalid`             | 401    |
| `"Bearer token not provided"`                    | `keycloak.token.missing`                    | 401    |
| `"Invalid client credentials"`                   | `keycloak.client.credentials.invalid`       | 401    |
| `"Invalid client or invalid client credentials"` | `keycloak.client.credentials.invalid`       | 401    |
| `"Client authentication failed"`                 | `keycloak.client.authentication.failed`     | 401    |
| `"Client not found"`                             | `keycloak.client.not.found`                 | 404    |
| `"Client disabled"`                              | `keycloak.client.disabled`                  | 403    |
| `"Client secret not provided"`                   | `keycloak.client.secret.missing`            | 400    |
| `"Invalid client secret"`                        | `keycloak.client.secret.invalid`            | 401    |
| `"Client not allowed for direct access grants"`  | `keycloak.client.direct.grant.disabled`     | 403    |
| `"Invalid parameter: redirect_uri"`              | `keycloak.request.redirect.invalid`         | 400    |
| `"Invalid redirect_uri"`                         | `keycloak.request.redirect.invalid`         | 400    |
| `"Missing parameter: grant_type"`                | `keycloak.request.grant.missing`            | 400    |
| `"Invalid request"`                              | `keycloak.request.invalid`                  | 400    |
| `"Invalid scope"`                                | `keycloak.scope.invalid`                    | 400    |
| `"Invalid response_type"`                        | `keycloak.response.type.invalid`            | 400    |
| `"Invalid response_mode"`                        | `keycloak.response.mode.invalid`            | 400    |
| `"Invalid code"` / `"Code not valid"`            | `keycloak.authorization.code.invalid`       | 400    |
| `"PKCE code verifier invalid"`                   | `keycloak.pkce.verifier.invalid`            | 400    |
| `"PKCE verification failed"`                     | `keycloak.pkce.verification.failed`         | 400    |
| `"Authentication failed"`                        | `keycloak.authentication.failed`            | 401    |
| `"Identity provider login failure"`              | `keycloak.identity.provider.failure`        | 401    |
| `"Brokered identity provider error"`             | `keycloak.identity.provider.broker.error`   | 401    |
| `"User already exists"`                          | `keycloak.user.already.exists`              | 409    |
| `"Email already exists"`                         | `keycloak.email.already.exists`             | 409    |
| `"Invalid username"`                             | `keycloak.username.invalid`                 | 400    |
| _(unknown)_                                      | `<errorDescription>`                        | 500    |

### Role Synchronizer

`KeycloakRoleSynchronizer` — `ApplicationRunner` that runs at startup:

1. `RoleDefinitionScanner` scans `@AuthRoles` beans → `List<ScannedResource(clientId, resourceDef, roles)>`
2. For each resource: finds or creates Keycloak client
3. Syncs roles (creates missing ones)
4. Syncs features (stored as JSON in client `features` attribute)
5. Syncs custom attributes (from `@AttributeDef`)

### Security Annotations

**`@AuthRoles`** — marks class as role definition source

```java
@AuthRoles(resources = {
        @ResourceDef(code = "my-svc", name = "My Service",
                attributes = @AttributeDef(key = "tier", value = "premium"),
                features = @FeatureDef(code = "user-mgmt", name = "User Management"))
})
@Component
public class Roles {
    // clientId:resource:action format — clientId must match @ResourceDef.code
    public static final String USER_VIEW = "my-svc:user:view";
    public static final String USER_EDIT = "my-svc:user:edit";
}
```

**`@ResourceDef`** — `code()`, `name()`, `description()`, `attributes()` (AttributeDef[]), `features()` (FeatureDef[])
**`@AttributeDef`** — `key()`, `value()` — custom Keycloak client attributes
**`@FeatureDef`** — `code()`, `name()`, `description()` — feature flags stored as JSON
