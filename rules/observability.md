---
name: observability
description: Observability rules — structured logging (JSON/ECS), Micrometer Observation API, distributed tracing, SLO-based alerting, cardinality management
globs: "*.java,*.yml,*.yaml"
---

# Observability Rules

Observability requires three signals working together: **logs** (what happened), **metrics** (how the system behaves), and **traces** (how requests flow). No single signal is sufficient.

## Structured Logging

Unstructured text logs are unmaintainable at scale — they require regex parsing and break on format changes. Use structured logging from day one.

- ALWAYS use SLF4J (`log.info/warn/error`) — NEVER `System.out.println` or `System.err`
- ALWAYS use structured format: Spring Boot 3.4+ supports `logging.structured.format.console=ecs` natively
- ALWAYS include context: `log.info("Order created: orderId={}, userId={}", orderId, userId)`
- ALWAYS propagate `correlationId` via MDC at request entry — include `traceId` and `spanId` for correlation
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

Spring Boot 3.x uses Micrometer Observation API as the native instrumentation facade. Write instrumentation against Observation — it auto-generates metrics AND traces from a single definition.

- ALWAYS instrument: request latency, error rate, queue depth, connection pool utilization
- ALWAYS use standard metric names: `http.server.requests`, `db.pool.active`, `cache.gets`
- ALWAYS add low-cardinality tags: `method`, `uri`, `status`, `outcome`
- ALWAYS export via OTLP (OpenTelemetry Protocol) — not proprietary vendor APIs
- PREFER `@Timed` annotation for latency (auto-generates percentile histograms)
- PREFER `Timer` for latency, `Counter` for totals, `Gauge` for current state, `DistributionSummary` for value distributions

### Cardinality Management (CRITICAL)

High-cardinality labels crash Prometheus/TSDB and are the #1 cause of metrics infrastructure failures:

| Tag Type | OK | DANGEROUS |
|----------|----|---------|
| Low cardinality | `region`, `service`, `status`, `method` | — |
| High cardinality | — | `userId`, `requestId`, `orderId`, `email` |

**Rule**: If a tag can have >100 unique values, it MUST NOT be a metric label. Use logs or traces for high-cardinality data instead.

## Distributed Tracing

- ALWAYS propagate trace headers (`traceparent` W3C standard, `X-Request-Id` for legacy)
- ALWAYS include `traceId` and `spanId` in MDC for log-trace correlation
- ALWAYS use Micrometer Context Propagation with `Hooks.enableAutomaticContextPropagation()` in reactive chains
- PREFER Micrometer Tracing over raw OpenTelemetry SDK — it's Spring-native, supports GraalVM, and auto-instruments Spring components

## Health Checks

- ALWAYS expose `/actuator/health` for liveness (Kubernetes readiness/liveness probes)
- ALWAYS add custom health indicators for critical dependencies (DB, Redis, Kafka, external APIs)
- ALWAYS set timeouts on health indicator checks (a hanging DB check blocks the health endpoint)
- ALWAYS secure non-health actuator endpoints (`/actuator/**` requires authentication)

## Alerting Philosophy

Threshold-based alerting ("alert if latency > 500ms") causes alert fatigue and misses gradual degradation. Use SLO-based alerting instead:

- Define **Service Level Objectives** (SLOs) for critical services: e.g., "99.9% of requests complete in <500ms"
- Alert on **burn rate** — how fast you're consuming your error budget
- Use multi-window alerting to reduce false positives (short window for fast alerts + long window for confirmation)

## Related Skills

- **observability-patterns** — Full Logback config, reactive MDC propagation, Micrometer auto-instrumentation, Prometheus config
- **spring-patterns** — WebFilter for correlation ID injection
- **testing-workflow** — Health indicator testing
