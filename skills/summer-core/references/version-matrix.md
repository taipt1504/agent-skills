# Summer Framework — Version Matrix

> Single source of truth for **which feature shipped in which version**, mirrored from
> [`common-libs/CHANGELOG.md`](https://git.newera.inc/cex-platform/common-libs/java-common-ms/-/blob/main/CHANGELOG.md).
> Update whenever a new Summer release ships. See `versions/_template.md` for per-version doc
> conventions.

**Latest stable:** 0.3.3 (2026-05-07)

## Pattern detection (auto-detect from project)

When you can't read `gradle.properties`, fall back to these signals:

| Signal in source | Lower bound |
|---|---|
| `SummerGlobalExceptionHandler` | 0.2.1+ |
| `summer-jwt-resource-server` artifact | 0.2.1+ |
| `RateLimiterService` | 0.2.2+ |
| `sync-role.enabled` (not `.enable`) | 0.2.3+ |
| `KeycloakException` with ~50+ mappings | 0.2.3+ |
| `keycloak.*` shared block (not under `sync-role.*`) | 0.2.4+ |
| `GroupRoleResolver` / `group-role-authorization` | 0.2.4+ |
| `Ufid` / `summer-payment-sdk` artifact | 0.2.5+ |
| `@Compact` annotation (not `@Hex`) | 0.2.6+ |
| `@TX` annotation (not `@TXN`) | 0.2.6+ |
| `Ufid.fromBase32()` / `UfidDisplay` | 0.2.8+ |
| `OutboxProperties.Cdc` (nested) / `f8a.outbox.publisher.mode: cdc` | 0.2.8+ |
| Outbox `next_retry_at` column / `OutboxBackoff` | 0.2.8+ |
| `io.f8a.summer.payment.event.ledger.*` (subpackages) | 0.2.9+ |
| `JwtBlacklistChecker` / `blacklist-prefix-key` | 0.3.0+ |
| `f8a.outbox.publisher.scheduler.*` (nested) | 0.3.1+ |
| `summer-kafka-consumer` artifact / `OutboxConsumerIdempotency` | 0.3.1+ |
| `KafkaOutboxPublisher` auto-wired | 0.3.1+ |
| `f8a.outbox.publisher.cdc.bootstrap-servers` (Kafka storage) | 0.3.1+ |
| `f8a.security.apisix.resource-server.providers.<id>` | 0.3.0+ |
| `MultiRealmAuthenticationConverter` | 0.3.2+ |
| `sync-role: <provider-id>` (top-level pointer) | 0.3.2+ |
| Per-provider `group-role-authorization: true` | 0.3.2+ |
| `GroupRoleResolver` with `scopeKey` constructor | 0.3.2+ |
| `GroupRoleInvalidator.BROADCAST_SCOPE` / single-arg `invalidate(String)` | 0.3.3+ |
| `Provider.issuerUri` config field | 0.3.3+ |

When unclear, ask the user. Never guess.

## Module × version

Legend: ● = added · ◐ = breaking change · ○ = additive only · — = no change · ✕ = removed

| Module | 0.2.1 | 0.2.2 | 0.2.3 | 0.2.4 | 0.2.5 | 0.2.6 | 0.2.8 | 0.2.9 | 0.3.0 | 0.3.1 | 0.3.2 | 0.3.3 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `summer-core` | ◐ | — | — | — | ● UFID | ◐ Ufid Base32 | ◐ Ufid renames | — | — | — | — | — |
| `summer-rest` | ◐ Tracing/Handler | — | — | — | — | ○ WebFlux Ufid | ○ ServerWebInputException details | — | — | — | — | — |
| `summer-data` (audit) | ◐ AuditService API | — | — | — | — | — | — | — | — | — | — | — |
| `summer-data` (outbox) | ○ Validators | — | — | — | — | — | ◐ Properties redesign · ● CDC mode · ○ Retry | — | — | ◐ Config reshape · ● Kafka storage · ● `KafkaOutboxPublisher` | — | — |
| `summer-data` (kafka-consumer) | — | — | — | — | — | — | — | — | — | ● module added | — | — |
| `summer-security` (apisix) | ◐ module rename | — | ○ KC errors | ◐ keycloak block · ● group-role | — | — | — | — | ◐ AAM 3-arg ctor · ● JWT blacklist | — | ◐ multi-realm `providers.*` · ● sync-role pointer | ○ broadcast invalidator · ○ `issuer-uri` |
| `summer-security` (keycloak) | — | — | — | ● group-by-path · ● role-mappings · ● scopes | — | — | — | — | — | — | — | — |
| `summer-ratelimit` | — | ● module added | — | — | — | — | — | — | — | — | — | — |
| `summer-test` | ○ tests | — | — | — | — | — | — | — | — | — | — | — |
| `summer-payment-sdk` | — | — | — | — | ● module added | ◐ `@TX`, `@Compact` rename | ◐ Ufid encoding · ○ many Ufid APIs | ◐ event subpackages | — | ○ `@Link` | — | — |

## Headline changes per version

### 0.3.3 (2026-05-07)
- **`summer-security`**: optional `provider.issuer-uri`; broadcast group-role invalidation
  (`GroupRoleInvalidator.invalidate(groupName)` + `BROADCAST_SCOPE = "*"`).

### 0.3.2 (2026-04-20)
- **`summer-security`**: multi-realm authentication via `providers.<id>` map
  (replaces single `keycloak.*` block); `MultiRealmAuthenticationConverter` routes by `iss`;
  `sync-role` becomes a top-level pointer to a provider id; per-provider
  `group-role-authorization`; group-role cache scoped by provider id.
- **`summer-data` (outbox)**: Debezium Kafka storage now inherits SASL/SSL from
  `spring.kafka.*`; Swagger BOM aligned in `summer-platform`.

### 0.3.1 (2026-04-20)
- **`summer-data`**: outbox config reshaped (scheduler/CDC nested); Debezium storage moved JDBC →
  Kafka (BREAKING); `KafkaOutboxPublisher` auto-wired by default; outbox publish headers now
  `Map<String, byte[]>` (BREAKING); CDC `lsn` preserved across retries; new
  `summer-kafka-consumer` module — LSN-watermark-based consumer idempotency.
- **`summer-payment-sdk`**: `@Link` annotation.

### 0.3.0 (2026-04-15)
- **`summer-security`**: JWT blacklist via Redis (`blacklist-prefix-key`);
  `JwtBlacklistChecker` strategy interface; `ApisixAuthenticationManager` constructor now
  3-arg (BREAKING for direct instantiation).

### 0.2.9 (2026-04-14)
- **`summer-payment-sdk`**: event classes split into domain subpackages (BREAKING imports);
  `CustomerInfoEvent` expanded; `CustomerInfoEventType` enum.

### 0.2.8 (2026-04-12)
- **`summer-core`**: `UfidFormat` → `UfidDisplay` (rename); `@Compact` outputs 26-char
  Crockford Base32; `Ufid.fromHex()` / `toHex()` removed.
- **`summer-data` (outbox)**: events `id` UUID → Ufid; Debezium CDC mode; `OutboxScheduledTasks`
  split; unified retry+backoff (works in both modes); `OutboxProperties` redesign (BREAKING);
  schema `next_retry_at` column.
- **`summer-payment-sdk`**: `Ufid.toBase32()` / `fromBase32()` / `fromUInt128()`; default
  `@JsonCreator` accepts UUID/Base32/display.

### 0.2.6 (2026-04-02)
- **`summer-core`**: UFID display format switches hex → Crockford Base32; `@TXN` → `@TX`,
  `@Hex` → `@Compact`; `LedgerOperation.CAPTURE` → `POST`; `PhoneNumber.toString()` masks PII.
- **`summer-rest`**: WebFlux `String → Ufid` converter auto-registered.

### 0.2.5 (2026-03-30)
- **`summer-core`**: UFID introduced (128-bit, sortable); `summer-payment-sdk` module added with
  prefix annotations (`@JE`, `@TXN`, `@SE`, `@UfidPrefix`, `@Hex`); `UfidConverter` for R2DBC.

### 0.2.4 (2026-03-22)
- **`summer-security`**: Keycloak config moved to shared `keycloak` block (BREAKING);
  `UserInfoAuthenticationConverter` returns `Mono` (BREAKING); group-role authorization
  (alternative to `resource_access`); Keycloak group-by-path / role-mappings / client-scopes APIs.

### 0.2.3 (2026-03-09)
- **`summer-security`**: `KeycloakException` mappings expanded to ~50; `sync-role.enabled`
  (not `.enable`); `RoleDefinitionScanner` registered as Spring bean.

### 0.2.2 (2026-03-04)
- **`summer-ratelimit`**: new module — fixed-window, sliding-window, token-bucket strategies;
  Redis (Lua atomic) and in-memory backends; per-scope policies.

### 0.2.1 (2026-02-26)
- **`summer-core`**: `JsonErrorResponse` moves to `core.exception` with `timestamp` + `details`;
  `ViewableException` gains `.detail()` builder; `CommonExceptions` adds `NOT_ACCEPTABLE`,
  `UNSUPPORTED_MEDIA_TYPE`, `PAYLOAD_TOO_LARGE`; `JsonUtils` deleted.
- **`summer-rest`**: `GlobalExceptionHandler` → `SummerGlobalExceptionHandler` (BREAKING);
  custom tracing removed — use Micrometer + OpenTelemetry; `DownstreamException` maps to 500.
- **`summer-data`**: `audit(AuditLog)` builder; `auditNonEntity` arg order change (BREAKING);
  `AbstractTableValidator` base; `AuditTableValidator` + enhanced `OutboxTableValidator`;
  schema auto-detected (`f8a.{outbox,audit}.validate-schema` removed).
- **`summer-security`**: `summer-security-core` → `summer-jwt-resource-server` (BREAKING module
  rename); new `summer-apikey-resource-server`; `SecurityErrorResponseWriter`;
  `DefaultAuthenticationException` and `DefaultJwtConverter` rewritten.

## How to update this matrix

1. After Summer X.Y.Z is added to `common-libs/CHANGELOG.md`, add a column to the "Module ×
   version" table and a "Headline changes" entry.
2. For each affected skill, write or update `skills/<skill>/references/versions/X.Y.Z.md`.
3. If `X.Y.Z` introduces breaking changes, write `skills/summer-core/references/migrations/<from>-to-<to>.md`.
4. Update `skills/summer-core/SKILL.md` Pattern Detection signals if the new version exposes a
   detectable artifact name, class, or property.
5. If `X.Y.Z` becomes the new stable, update each affected skill's `SKILL.md` canon to match.
