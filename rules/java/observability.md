---
name: observability
description: Observability rules — structured logging (JSON/ECS), Micrometer Observation API, distributed tracing, SLO-based alerting, cardinality management
globs: "*.java,*.yml,*.yaml"
---

# Observability Rules

Observability requires three signals: **logs** (what happened), **metrics** (system behavior), **traces** (request flow). No single signal sufficient.

## Structured Logging

Unstructured logs are unmaintainable at scale — require regex parsing, break on format changes. Use structured logging from day one.

- ALWAYS use SLF4J (`log.info/warn/error`) — NEVER `System.out.println` or `System.err`
- ALWAYS structured format: Spring Boot 3.4+ supports `logging.structured.format.console=ecs` natively
- ALWAYS include context: `log.info("Order created: orderId={}, userId={}", orderId, userId)`
- ALWAYS propagate `correlationId` via MDC at request entry — include `traceId` and `spanId`
- ALWAYS clear MDC in reactive chains via `doFinally()` — leaked MDC contaminates unrelated requests
- NEVER log PII, passwords, tokens, credit cards, or full request/response bodies
- NEVER log at INFO in hot loops — use DEBUG with `log.isDebugEnabled()` guard (avoids string allocation)

### Log Levels

| Level | Use For | Production Impact | Example |
|-------|---------|-------------------|---------|
| ERROR | Unexpected failures requiring human attention | Pages on-call | DB connection lost, unhandled exception |
| WARN | Degraded but functional, or recoverable failures | Tracked in dashboards | Retry succeeded after failure, cache miss fallback |
| INFO | Business events, state transitions | High-value audit trail | Order created, payment processed, user logged in |
| DEBUG | Developer diagnostics | Disabled in production | Method entry/exit, intermediate values |

### Sensitive Data Rules

```java
// BAD — logs password and token
log.info("User login: email={}, password={}, token={}", email, password, token);

// GOOD — mask sensitive fields, include correlation
log.info("User login: email={}, correlationId={}", maskEmail(email), MDC.get("correlationId"));
```

## Metrics (Micrometer Observation API)

Spring Boot 3.x uses Micrometer Observation API as native instrumentation facade. Write instrumentation against Observation — auto-generates metrics AND traces from single definition.

- ALWAYS instrument: request latency, error rate, queue depth, connection pool utilization
- ALWAYS standard metric names: `http.server.requests`, `db.pool.active`, `cache.gets`
- ALWAYS low-cardinality tags: `method`, `uri`, `status`, `outcome`
- ALWAYS export via OTLP — not proprietary vendor APIs
- PREFER `@Timed` for latency (auto-generates percentile histograms)
- PREFER `Timer` for latency, `Counter` for totals, `Gauge` for current state, `DistributionSummary` for value distributions

### Cardinality Management (CRITICAL)

High-cardinality labels crash Prometheus/TSDB — #1 cause of metrics infrastructure failures:

| Tag Type | OK | DANGEROUS |
|----------|----|---------|
| Low cardinality | `region`, `service`, `status`, `method` | — |
| High cardinality | — | `userId`, `requestId`, `orderId`, `email` |

**Rule**: Tag with >100 unique values MUST NOT be metric label. Use logs or traces for high-cardinality data.

## Distributed Tracing

- ALWAYS propagate trace headers (`traceparent` W3C, `X-Request-Id` for legacy)
- ALWAYS include `traceId` and `spanId` in MDC for log-trace correlation
- ALWAYS use Micrometer Context Propagation with `Hooks.enableAutomaticContextPropagation()` in reactive chains
- PREFER Micrometer Tracing over raw OpenTelemetry SDK — Spring-native, supports GraalVM, auto-instruments Spring components

## Health Checks

- ALWAYS expose `/actuator/health` for liveness (Kubernetes readiness/liveness probes)
- ALWAYS add custom health indicators for critical dependencies (DB, Redis, Kafka, external APIs)
- ALWAYS set timeouts on health indicator checks (hanging DB check blocks health endpoint)
- ALWAYS secure non-health actuator endpoints (`/actuator/**` requires authentication)

## Alerting Philosophy

Threshold alerting ("alert if latency > 500ms") causes alert fatigue, misses gradual degradation. Use SLO-based alerting:

- Define **SLOs** for critical services: e.g., "99.9% of requests complete in <500ms"
- Alert on **burn rate** — how fast error budget is consumed
- Multi-window alerting to reduce false positives (short window for fast alerts + long window for confirmation)

## Related Rules

- `rules/java/code-review-core.md` — `CORE-LOG-001` SLF4J parameterized · `CORE-LOG-002` no sensitive data · `CORE-LOG-003` log levels · `CORE-LOG-004` structured logging · `CORE-LOG-005` MDC correlation
- `rules/java/code-review-crosscut.md` — `XCT-OBS-001` Micrometer metrics · `XCT-OBS-002` OpenTelemetry tracing · `XCT-OBS-003` health checks
- `rules/java/code-review-reactor.md` — `RX-CTX-001` Reactor Context for MDC propagation

## Related Skills

- **observability-patterns** — Full Logback config, reactive MDC propagation, Micrometer auto-instrumentation, Prometheus config
- **spring-webflux-patterns** — WebFilter for correlation ID injection
- **testing-workflow** — Health indicator testing
