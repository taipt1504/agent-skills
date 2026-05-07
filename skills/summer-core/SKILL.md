---
name: summer-core
description: Gate skill for Summer Framework detection and shared types. MUST load first — verifies io.f8a.summer:summer-platform in build.gradle/pom.xml. If NOT FOUND, do NOT load any summer sub-skill. Provides version detection, module overview, shared domain types, and sub-skill routing.
triggers:
  natural: ["summer framework", "summer platform"]
  code: ["io.f8a.summer", "summer-platform"]
requires: []
---

# Summer Core — Gate & Shared Types

Reactive Spring Boot 3.x library (Java 21+) on WebFlux + Reactor Netty.
**Group:** `io.f8a.summer` | **BOM:** `summer-platform` | **Latest stable:** 0.3.3 (2026-05-07)

## Hard Gate

Check `build.gradle` or `pom.xml` for `io.f8a.summer:summer-platform`.
**NOT FOUND → STOP. Do not load any summer sub-skill.**

## Version Detection

1. Read `gradle.properties` → `version=X.Y.Z`.
2. Check `build.gradle` for `summer-platform` version.
3. Pattern detection — primary signals:

   | Signal | Version |
   |---|---|
   | `Provider.issuerUri` config field / `BROADCAST_SCOPE` | 0.3.3+ |
   | `MultiRealmAuthenticationConverter` / `providers.<id>` schema | 0.3.2+ |
   | `summer-kafka-consumer` artifact / `KafkaOutboxPublisher` auto-bean | 0.3.1+ |
   | `JwtBlacklistChecker` / `blacklist-prefix-key` | 0.3.0+ |
   | `OutboxProperties.Cdc` (nested) / `f8a.outbox.publisher.mode: cdc` | 0.2.8+ |
   | `@Compact` (not `@Hex`) / `@TX` (not `@TXN`) | 0.2.6+ |
   | `Ufid` / `summer-payment-sdk` artifact | 0.2.5+ |
   | `GroupRoleResolver` / `group-role-authorization` | 0.2.4+ |
   | `keycloak.*` shared block (not under `sync-role.*`) | 0.2.4+ |
   | `sync-role.enabled` (not `.enable`) | 0.2.3+ |
   | `RateLimiterService` | 0.2.2+ |
   | `SummerGlobalExceptionHandler` / `summer-jwt-resource-server` | 0.2.1+ |

4. If unclear → ask the user. Never guess.

When the detected version is older than the latest stable, load the matching
`<skill>/references/versions/<version>.md` overlay alongside the canonical `SKILL.md`. See
[references/version-matrix.md](references/version-matrix.md) for the full feature × version table.

## Module Overview (current — 0.3.x)

| Module                             | Config Prefix                                                                    | Activation [^1]                                  |
|------------------------------------|----------------------------------------------------------------------------------|--------------------------------------------------|
| `summer-rest-autoconfigure`        | `f8a.common`                                                                     | Auto                                             |
| `summer-data-autoconfigure`        | —                                                                                | Auto                                             |
| `summer-data-audit-autoconfigure`  | `f8a.audit`                                                                      | Auto                                             |
| `summer-data-outbox-autoconfigure` | `f8a.outbox.publisher.{queue, scheduler.*, cdc.*}` (0.3.1+)                      | `f8a.outbox.enabled=true` (default)              |
| `summer-kafka-consumer-autoconfigure` (0.3.1+) | `f8a.kafka.consumer.{idempotency.*, retry.*}`                        | Auto when `summer-kafka-consumer` on classpath   |
| `summer-security-autoconfigure`    | `f8a.security.apisix.resource-server.providers.<id>` (0.3.0+)                    | `enabled=true` (default since 0.2.3)             |
| `summer-ratelimit-autoconfigure`   | `f8a.rate-limiter`                                                               | Auto (0.2.2+ only)                               |
| `summer-keycloak` (client)         | —                                                                                | Manual bean creation                             |
| `summer-keycloak` (role sync)      | `f8a.security.apisix.resource-server.sync-role: <provider-id>` (0.3.2+)          | When `sync-role` points to a provider (0.3.2+)   |
| `summer-keycloak` (group-role)     | per-provider `group-role-authorization: true` + global `group-role-authorization.*` (0.3.2+) | `true` on a provider (0.3.2+)         |

[^1]: "Auto" means Spring Boot auto-configuration activates when the required dependency is on the classpath (Spring Boot for REST, R2DBC for data modules).

For 0.2.x schemas (single `keycloak.*` block, single `sync-role.enabled`, top-level
`group-role-authorization.enabled`) load the matching `<skill>/references/versions/0.2.x.md`.

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
- **[references/version-matrix.md](references/version-matrix.md)** — Feature × version matrix for every Summer module + pattern detection signals.
- **[references/versions/](references/versions/)** — Per-version notes for cross-cutting changes (UFID introduction, exception handler rewrite, etc.). Sub-skills carry their own version dirs.
- **[references/migrations/](references/migrations/)** — Step-by-step migration guides between major schema/version transitions.
- **[references/versioning-workflow.md](references/versioning-workflow.md)** — How to add a new Summer release to this repo (audience: maintainers).

## Related Skills

- **summer-rest** — Handlers, ResponseFactory, WebClientBuilderFactory
- **summer-data** — AuditService, OutboxService, R2DBC converters
- **summer-security** — APISIX auth, @AuthRoles, Keycloak
- **summer-ratelimit** — Rate limiting (0.2.2+)
- **summer-test** — PostgresTestContainer, WireMock, blackbox
