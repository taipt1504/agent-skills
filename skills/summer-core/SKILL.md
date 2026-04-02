---
name: summer-core
description: Gate skill for Summer Framework detection and shared types. MUST load first — verifies io.f8a.summer:summer-platform in build.gradle/pom.xml. If NOT FOUND, do NOT load any summer sub-skill. Provides version detection, module overview, shared domain types, and sub-skill routing.
triggers:
  natural: ["summer framework", "summer platform"]
  code: ["io.f8a.summer", "summer-platform"]
---

# Summer Core — Gate & Shared Types

Reactive Spring Boot 3.x library (Java 21+) on WebFlux + Reactor Netty.
**Group:** `io.f8a.summer` | **BOM:** `summer-platform`

## Hard Gate

Check `build.gradle` or `pom.xml` for `io.f8a.summer:summer-platform`.
**NOT FOUND → STOP. Do not load any summer sub-skill.**

## Version Detection

1. Read `gradle.properties` → `version=X.Y.Z`
2. Check `build.gradle` for `summer-platform` version
3. Pattern detection: `SummerGlobalExceptionHandler` → 0.2.1+ | `RateLimiterService` → 0.2.2+ | `sync-role.enabled` (not
   `.enable`) → 0.2.3+ | `GroupRoleResolver` or `group-role-authorization` → 0.2.4+
4. If unclear → ask the user. Never guess.

## Module Overview

| Module                             | Config Prefix                                                  | Activation [^1]                                  |
|------------------------------------|----------------------------------------------------------------|--------------------------------------------------|
| `summer-rest-autoconfigure`        | `f8a.common`                                                   | Auto                                             |
| `summer-data-autoconfigure`        | —                                                              | Auto                                             |
| `summer-data-audit-autoconfigure`  | `f8a.audit`                                                    | Auto                                             |
| `summer-data-outbox-autoconfigure` | `f8a.outbox`                                                   | `f8a.outbox.enabled=true` (default)              |
| `summer-security-autoconfigure`    | `f8a.security.apisix.resource-server`                          | `enabled=true` (default since 0.2.3)             |
| `summer-ratelimit-autoconfigure`   | `f8a.rate-limiter`                                             | Auto (0.2.2+ only)                               |
| `summer-keycloak` (client)         | —                                                              | Manual bean creation                             |
| `summer-keycloak` (role sync)      | `f8a.security.apisix.resource-server.sync-role`                | When `keycloak.server-url` is non-blank (0.2.4+) |
| `summer-keycloak` (group-role)     | `f8a.security.apisix.resource-server.group-role-authorization` | `enabled=true` (0.2.4+)                          |

[^1]: "Auto" means Spring Boot auto-configuration activates when the required dependency is on the classpath (Spring Boot for REST, R2DBC for data modules).

## Gradle Setup

Declare the BOM first; sub-skills list their own module dependencies.

```gradle
implementation platform('io.f8a.summer:summer-platform:<version>')
```

## Shared Types

| Type | Package | Purpose |
|---|---|---|
| `Member` | `core.security.authentication` | Authenticated user: id, username, givenName, familyName, email, authorities |
| `CallerAware` | `core.security.authentication` | Mixin → `getCaller()` returns `Mono<Member>` |
| `Password` | `core` | Value object; validate with `@ValidPassword` |
| `PhoneNumber` | `core` | Value object; validate with `@ValidPhoneNumber` |
| `ViewableException` | `core.exception` | Base HTTP exception with `.detail()` fluent builder |
| `JsonErrorResponse` | `core.exception` | Error response DTO: code, message, traceId, timestamp, details |

## CommonExceptions Enum

`RESOURCE_NOT_FOUND`(404), `INVALID_REQUEST`(400), `VALIDATION_ERROR`(422), `UNAUTHORIZED`(401), `ACCESS_DENIED`(403), `FORBIDDEN`(403), `CONFLICT`(409), `RATE_LIMIT_EXCEEDED`(429), `INTERNAL_SERVER_ERROR`(500), `SERVICE_UNAVAILABLE`(503), `TIMEOUT`(504), `NOT_ACCEPTABLE`(406), `UNSUPPORTED_MEDIA_TYPE`(415), `PAYLOAD_TOO_LARGE`(413).

Usage: `throw CommonExceptions.RESOURCE_NOT_FOUND.toException().detailValue("id", id);`

## Sub-Skill Router

| Context | Load |
|---|---|
| Handler, controller, WebClient, Jackson, exception handling | **summer-rest** |
| Audit, outbox, R2DBC converters, DDL | **summer-data** |
| APISIX auth, @AuthRoles, Keycloak client, role sync | **summer-security** |
| Rate limiting (0.2.2+) | **summer-ratelimit** |
| Tests, WireMock, Testcontainers, blackbox | **summer-test** |

## Sub-Skill Gate Verification

Every summer sub-skill MUST verify this gate was loaded. If a sub-skill is triggered directly, check build.gradle for `io.f8a.summer:summer-platform` before proceeding.

## Rules

- Never guess the Summer version — detect from gradle.properties or pattern matching, ask if unclear.
- Never load summer sub-skills without confirming the gate.
- Always check version compatibility before suggesting features (e.g., rate limiting requires 0.2.2+).
- Always use `ViewableException` (not generic RuntimeException) for HTTP error responses.

## References

- **[references/summer-types.md](references/summer-types.md)** — Full usage: Member, CallerAware, Password, PhoneNumber, ViewableException, JsonErrorResponse, CommonExceptions

## Related Skills

- **summer-rest** — Handlers, ResponseFactory, WebClientBuilderFactory
- **summer-data** — AuditService, OutboxService, R2DBC converters
- **summer-security** — APISIX auth, @AuthRoles, Keycloak
- **summer-ratelimit** — Rate limiting (0.2.2+)
- **summer-test** — PostgresTestContainer, WireMock, blackbox
