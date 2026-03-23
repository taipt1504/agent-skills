# Summer Framework — Common Patterns (All Versions)

Shared across all supported versions (0.2.1+). Version-specific differences are in `v0.2.x.md` files.

## Gradle Setup

```gradle
implementation platform('io.f8a.summer:summer-platform:<version>')
implementation 'io.f8a.summer:summer-rest-autoconfigure'       // REST + Jackson + WebClient
implementation 'io.f8a.summer:summer-data-autoconfigure'       // R2DBC converters
implementation 'io.f8a.summer:summer-data-audit-autoconfigure' // Audit trail
implementation 'io.f8a.summer:summer-data-outbox-autoconfigure'// Outbox pattern
implementation 'io.f8a.summer:summer-security-autoconfigure'   // APISIX security
implementation 'io.f8a.summer:summer-keycloak'                 // Keycloak client + role sync
testImplementation 'io.f8a.summer:summer-test'                 // WireMock + TestContainers
```

Modules added in specific versions:

- `summer-ratelimit-autoconfigure` — **0.2.2+** only
- `summer-apikey-resource-server` — **0.2.1+** (split from old `summer-security-core`)

## Modules At a Glance

| Module                             | Config Prefix                                                  | Activation                                       |
|------------------------------------|----------------------------------------------------------------|--------------------------------------------------|
| `summer-rest-autoconfigure`        | `f8a.common`                                                   | Auto (Spring Boot on classpath)                  |
| `summer-data-autoconfigure`        | —                                                              | Auto (R2DBC on classpath)                        |
| `summer-data-audit-autoconfigure`  | `f8a.audit`                                                    | Auto (R2DBC on classpath)                        |
| `summer-data-outbox-autoconfigure` | `f8a.outbox`                                                   | `f8a.outbox.enabled=true` (default true)         |
| `summer-security-autoconfigure`    | `f8a.security.apisix.resource-server`                          | `enabled=true` (default true since 0.2.3)        |
| `summer-jwt-resource-server`       | —                                                              | Transitive via security-autoconfigure            |
| `summer-apikey-resource-server`    | —                                                              | Manual (`ReactiveApiKeyWebFilter`)               |
| `summer-ratelimit-autoconfigure`   | `f8a.rate-limiter`                                             | Auto (0.2.2+ only)                               |
| `summer-keycloak` (client)         | —                                                              | Manual bean creation                             |
| `summer-keycloak` (role sync)      | `f8a.security.apisix.resource-server.sync-role`                | When `keycloak.server-url` is non-blank (0.2.4+) |
| `summer-keycloak` (group-role)     | `f8a.security.apisix.resource-server.group-role-authorization` | `enabled=true` (0.2.4+)                          |

## Exception Handling

Use `ViewableException` (or `CommonExceptions` enum) for HTTP errors. Supports structured field-level error details:

```java
// Simple — just code + status
throw new ViewableException("user.not.found", HttpStatus.NOT_FOUND);

// Using the enum
throw CommonExceptions.RESOURCE_NOT_FOUND.toException();

// With field-level details (fluent builder)
throw CommonExceptions.VALIDATION_ERROR.toException()
    .detail("email", "Invalid email format", request.getEmail())
    .detail("age", "Must be at least 18", String.valueOf(request.getAge()));

// With issue only (no value)
throw CommonExceptions.INVALID_REQUEST.toException()
    .detailIssue("password", "Must contain at least one uppercase letter");

// With value only (no issue)
throw CommonExceptions.CONFLICT.toException()
    .detailValue("username", request.getUsername());
```

`SummerGlobalExceptionHandler` serializes to `JsonErrorResponse`:

```json
{
  "code": "com.validation.error",
  "message": "...",
  "traceId": "abc123",
  "timestamp": "2026-03-04T10:30:00Z",
  "details": [
    { "field": "email", "issue": "Invalid email format", "value": "bad-email" },
    { "field": "age", "issue": "Must be at least 18", "value": "15" }
  ]
}
```

Common codes: `RESOURCE_NOT_FOUND` (404), `INVALID_REQUEST` (400), `VALIDATION_ERROR` (422), `UNAUTHORIZED` (401),
`ACCESS_DENIED` (403), `FORBIDDEN` (403), `CONFLICT` (409), `RATE_LIMIT_EXCEEDED` (429), `INTERNAL_SERVER_ERROR` (500),
`SERVICE_UNAVAILABLE` (503), `TIMEOUT` (504).

## Security (APISIX)

APISIX gateway validates JWT, forwards `X-Userinfo` header (Base64 JSON). Summer decodes it.

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

**Roles & Resources:** define with `@AuthRoles` + `@ResourceDef` + role constants in `clientId:resource:action` format:

```java
@AuthRoles(resources = {
    @ResourceDef(
        code = "my-svc",
        name = "My Service",
        description = "Backend service",
        attributes = { @AttributeDef(key = "isPortal", value = "true") },
        features = {
            @FeatureDef(code = "user-mgmt", name = "User Management", description = "CRUD users")
        }
    )
})
@Component
public class Roles {
    public static final String USER_VIEW = "my-svc:user:view";
    public static final String USER_EDIT = "my-svc:user:edit";
}
```

Enforce with `@PreAuthorize("hasAnyRole(@roles.USER_VIEW)")`.

**Annotations (in `summer-core`):**

- `@AuthRoles` — marks class as role definition source; `resources()` array of `@ResourceDef`
- `@ResourceDef` — defines a Keycloak client; `code()`, `name()`, `description()`, `attributes()`, `features()`
- `@AttributeDef` — custom Keycloak client attribute; `key()`, `value()`
- `@FeatureDef` — feature flag; `code()`, `name()`, `description()`

## Keycloak Client

`ReactiveKeycloakClient` — reactive resource-based API (mirrors official keycloak-admin-client SPI pattern).
Self-creates its own `WebClient` from `KeycloakConfig.serverUrl`. Uses `KeycloakTokenProvider` for in-memory cached
admin tokens (client_credentials + refresh).

```java
var config = new KeycloakConfig();
config.setServerUrl("https://keycloak.example.com");
config.setRealm("my-realm");
config.setClientId("admin-cli");
config.setClientSecret("secret");

var keycloak = new ReactiveKeycloakClient(config);
```

### Resource Navigation API

```java
// Users
keycloak.users().create(userRep);                           // Mono<String> (userId)
keycloak.users().list(0, 10);                               // Flux<UserRepresentation>
keycloak.users().search("john", true);                      // Flux<UserRepresentation>
keycloak.users().count();                                   // Mono<Integer>
keycloak.users().get(userId).toRepresentation();            // Mono<UserRepresentation>
keycloak.users().get(userId).update(userRep);               // Mono<Void>
keycloak.users().get(userId).remove();                      // Mono<Void>
keycloak.users().get(userId).resetPassword(credRep);        // Mono<Void>
keycloak.users().get(userId).logout();                      // Mono<Void>

// Clients
keycloak.clients().create(clientRep);                       // Mono<String> (clientUuid)
keycloak.clients().findAll();                               // Flux<ClientRepresentation>
keycloak.clients().findByClientId("my-client");             // Flux<ClientRepresentation>
keycloak.clients().get(uuid).toRepresentation();            // Mono<ClientRepresentation>
keycloak.clients().get(uuid).update(clientRep);             // Mono<Void>
keycloak.clients().get(uuid).roles().list();                // Flux<RoleRepresentation>
keycloak.clients().get(uuid).roles().create(roleRep);       // Mono<Void>

// Token operations (no admin auth — uses separate non-auth WebClient)
keycloak.tokenResource().grantToken(user, pass);                          // Mono<AccessTokenResponse>
keycloak.tokenResource().refreshToken(refreshToken);                      // Mono<AccessTokenResponse>
keycloak.tokenResource().clientCredentials(clientId, secret, scope);      // Mono<AccessTokenResponse>
keycloak.tokenResource().introspect(token);                               // Mono<Map<String,Object>>
keycloak.tokenResource().userInfo(accessToken);                           // Mono<Map<String,Object>>
keycloak.tokenResource().logout(refreshToken);                            // Mono<Void>

// Realm scoping
keycloak.realm();              // ReactiveRealmResource (default realm from config)
keycloak.realm("other-realm"); // ReactiveRealmResource (explicit realm)
```

Uses `org.keycloak.representations.idm.*` DTOs: `UserRepresentation`, `ClientRepresentation`, `RoleRepresentation`,
`CredentialRepresentation`, `AccessTokenResponse`.

`KeycloakException` extends `ViewableException`. See version-specific files for error mapping scope (expanded
significantly in 0.2.3).

### Role Synchronizer

`KeycloakRoleSynchronizer` — `ApplicationRunner` that syncs `@AuthRoles` definitions to Keycloak at startup. Syncs:
clients, roles, features (as client attribute JSON), custom attributes.

See version-specific files for activation behavior (changed in 0.2.3).

## Audit Logging

Auto-activates with R2DBC. Requires `audit_log` table (see `api_reference.md` for DDL).
`AuditTableValidator` validates schema on startup (disable with `f8a.audit.validate-on-startup=false`).

### Primary: `audit(AuditLog)` — build with builder, auto-fills null fields

```java
// Minimal: action + intent (actor, request info, timestamps auto-filled from context)
auditService.audit(AuditLog.builder()
    .action("LOGIN").intent("USER_REQUEST").build());

// With entity context
auditService.audit(AuditLog.builder()
    .action("APPROVE").intent("USER_REQUEST")
    .entityType("Order").entityId(orderId)
    .comment("Approved order").build());

// With before/after JSON payloads
auditService.audit(AuditLog.builder()
    .action("UPDATE").intent("SYSTEM_SYNC")
    .entityType("ExchangeRate").entityId(pair)
    .oldValues(mapper.valueToTree(old))
    .newValues(mapper.valueToTree(updated)).build());

// Override actor (skips security context lookup when actorId is set)
auditService.audit(AuditLog.builder()
    .action("CLEANUP").intent("SCHEDULED_JOB")
    .actorId("scheduler").actorUsername("cleanup-job").build());
```

### Convenience methods for entity CRUD

```java
auditService.auditCreate(entity, "USER_REQUEST", "Created user");          // Mono<Void>
auditService.auditUpdate(oldEntity, newEntity, "USER_REQUEST", "Updated"); // Mono<Void>
auditService.auditDelete(entity, "USER_REQUEST", "Deleted user");          // Mono<Void>
auditService.auditNonEntity("LOGIN", "USER_REQUEST", "User logged in");    // Mono<Void>
```

**Note:** `auditNonEntity` param order is `(action, intent, comment)` since 0.2.1. Pre-0.2.1 was
`(intent, action, comment)`.

### Annotation-based (Mono/Flux return types only)

```java
@Audit(action = "UPDATE", comment = "Updated config") // defaults: action="TRACE", intent="USER_REQUEST"
public Mono<Void> updateConfig(ConfigRequest req) { ... }

@AuditField String name;  // marks field for diff tracking in diffValues
```

## Outbox Pattern

Transactional outbox with scheduled publishing, circuit breaker, cleanup.

```java
// 1. Implement publisher
@Component
public class KafkaPublisher implements OutboxEventPublisher {
    public Mono<Void> publish(OutboxEvent event) { /* send to broker */ }
    public String getPublisherName() { return "kafka"; }
}
// 2. Save events in business logic
outboxService.saveEvent("ORDER_CREATED", orderId, payloadJson);
```

Requires `outbox_events` table (see `api_reference.md` for DDL).

## WebClient

`WebClientBuilderFactory` (auto-configured) creates pooled clients with trace propagation:

```java
WebClient client = factory.newClient(
  WebClientBuilderOptions.builder()
    .baseUrl("https://api.example.com")
    .errorHandling(false)
    .build());
```

## Testing

```java
PostgresTestContainer pg = new PostgresTestContainer();
pg.runFlywayMigrations("db/migration");

WireMockServiceManager wm = new WireMockServiceManager();
wm.startService("payment-service", 8081);
```

## Key Types Quick Reference

| Type                      | Package                        | Purpose                                                     |
|---------------------------|--------------------------------|-------------------------------------------------------------|
| `ViewableException`       | `core.exception`               | Base HTTP exception                                         |
| `JsonErrorResponse`       | `core.exception`               | Error response DTO (moved from `rest-common` in 0.2.1)      |
| `Member`                  | `core.security.authentication` | Authenticated user info                                     |
| `CallerAware`             | `core.security.authentication` | Mixin for `getCaller()` -> `Mono<Member>`                   |
| `BaseController`          | `core.pattern.handler`         | Base class for handler-pattern controllers                  |
| `ResponseFactory`         | `rest-common.factory`          | Auto-registered bean for building response entities         |
| `WebClientBuilderFactory` | `core.webclient`               | Create configured WebClients                                |
| `AuditService`            | `core.audit`                   | Audit trail operations                                      |
| `OutboxService`           | `core.outbox`                  | Outbox event operations                                     |
| `RateLimiterService`      | `core.ratelimit`               | Rate limiting (0.2.2+)                                      |
| `RateLimitKey`            | `core.ratelimit`               | Key record (identifier + policyKey) (0.2.2+)                |
| `RateLimitResult`         | `core.ratelimit`               | Result record (allowed, limit, remaining, resetAt) (0.2.2+) |
| `ReactiveKeycloakClient`  | `keycloak`                     | Keycloak resource-based API client                          |
| `KeycloakTokenProvider`   | `keycloak`                     | In-memory cached admin token management                     |
| `KeycloakException`       | `keycloak`                     | Keycloak error -> ViewableException                         |
| `@AuthRoles`              | `core.security`                | Role + resource definition marker                           |
| `@ResourceDef`            | `core.security`                | Keycloak client definition                                  |
| `@FeatureDef`             | `core.security`                | Feature flag definition                                     |
| `@AttributeDef`           | `core.security`                | Custom client attribute                                     |
| `@Audit`                  | `core.audit`                   | Annotation-based auditing                                   |
| `@Handler`                | `rest-common`                  | Handler bean marker                                         |
