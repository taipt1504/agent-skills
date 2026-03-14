# Observability Rules

## Structured Logging

- ALWAYS use SLF4J (`log.info/warn/error`) — NEVER `System.out.println`
- ALWAYS include context: `log.info("Order created: orderId={}", orderId)`
- ALWAYS `MDC.put("correlationId", ...)` at request entry — propagate through chain
- ALWAYS log at correct level: ERROR (failures), WARN (degraded), INFO (business events), DEBUG (dev)
- NEVER log PII, passwords, tokens, credit cards, or full request bodies
- NEVER log at INFO in hot loops — use DEBUG with `log.isDebugEnabled()` guard

## Log Levels

| Level | Use For | Example |
|-------|---------|---------|
| ERROR | Unexpected failures requiring attention | DB connection lost, unhandled exception |
| WARN | Degraded but functional, recoverable | Retry succeeded, cache miss fallback |
| INFO | Business events, state transitions | Order created, payment processed |
| DEBUG | Developer diagnostics | Method entry/exit, intermediate values |

## Metrics (Micrometer)

- ALWAYS instrument: request latency, error rate, queue depth, pool utilization
- ALWAYS use standard metric names: `http.server.requests`, `db.pool.active`
- ALWAYS add tags: `method`, `uri`, `status`, `exception`
- PREFER `Timer` for latency, `Counter` for totals, `Gauge` for current state
- NEVER create high-cardinality tags (user IDs, request IDs as tag values)

## Distributed Tracing

- ALWAYS propagate trace headers (`X-Request-Id`, `traceparent`)
- ALWAYS include `correlationId` in MDC for log correlation
- PREFER Spring Cloud Sleuth / Micrometer Tracing for auto-instrumentation

## Health Checks

- ALWAYS expose `/actuator/health` for liveness
- ALWAYS add custom health indicators for critical dependencies (DB, Redis, Kafka)
- ALWAYS secure other actuator endpoints (`/actuator/**` requires ADMIN)

## Detailed Patterns

For implementation examples, see:
- `skills/observability-patterns` — Micrometer setup, tracing config, alert rules
