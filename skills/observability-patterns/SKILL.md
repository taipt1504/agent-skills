---
name: observability-patterns
description: >
  Observability patterns for Spring Boot — structured logging, distributed tracing,
  custom metrics, health checks, alerting, and Prometheus monitoring. Use when adding
  logging to services, configuring log formats, setting up distributed tracing, creating
  custom Micrometer metrics, configuring health endpoints, writing Prometheus alert rules,
  or setting up Grafana dashboards.
triggers:
  natural: ["structured logging", "metrics", "distributed tracing", "health check", "alerting"]
  code: ["Micrometer", "@Timed", "MeterRegistry", "logback", "MDC"]
---

# Observability Patterns for Spring Boot

## Structured Logging

### Logback JSON (Production)

```xml
<springProfile name="!local">
  <appender name="JSON_CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="net.logstash.logback.encoder.LogstashEncoder">
      <customFields>{"service":"order-service","env":"${SPRING_PROFILES_ACTIVE}"}</customFields>
    </encoder>
  </appender>
</springProfile>
```

### Log Levels

| Level | Use For |
|-------|---------|
| ERROR | Failures requiring attention (exceptions, data loss) |
| WARN | Recoverable issues (fallback triggered, retry) |
| INFO | Business events (order created, payment processed) |
| DEBUG | Technical detail (query params, cache hits) — local only |

### Rules

- Use SLF4J placeholders: `log.info("Order created orderId={}", order.id())` — never concatenation.
- MDC for context: `MDC.put("orderId", id)`. Clear in `finally`.
- Never log PII (card numbers, passwords). Log identifiers only.

## Reactive Context Propagation

```java
public Mono<Order> createReactive(CreateOrderCommand cmd) {
    return Mono.deferContextual(ctx -> {
        MDC.put("traceId", ctx.getOrDefault("traceId", "none"));
        MDC.put("orderId", cmd.orderId());
        return orderRepository.save(Order.from(cmd))
            .doOnNext(o -> log.info("Order created orderId={}", o.id()))
            .doOnError(e -> log.error("Order creation failed", e))
            .doFinally(sig -> MDC.clear());
    });
}
```

## Distributed Tracing

```yaml
management:
  tracing:
    sampling:
      probability: 1.0  # 100% dev; 0.1 (10%) prod
  otlp:
    tracing:
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://localhost:4318}/v1/traces
```

Create custom spans for meaningful operations with `tracer.nextSpan().name("order.enrich").tag(...)`. Use `WebClient.builder().observationRegistry(registry)` for automatic trace propagation.

## Custom Metrics

- **Counter**: `Counter.builder("orders.created.total").register(meterRegistry)` — totals.
- **Timer**: `Timer.builder("orders.creation.duration").register(meterRegistry).record(() -> work())` — latency.
- **Gauge**: `Gauge.builder("orders.pending.count", this, s -> s.count()).register(meterRegistry)` — current value.
- **@Timed** on controllers, **@Observed** on business methods.

### Prometheus Config

```yaml
management:
  endpoints.web.exposure.include: health,metrics,prometheus
  endpoint.health.probes.enabled: true
  metrics.distribution:
    percentiles-histogram:
      http.server.requests: true
    slo:
      http.server.requests: 50ms,200ms,500ms,1s
```

## Health Indicators & Kubernetes Probes

```java
@Component
public class ExternalServiceHealthIndicator implements HealthIndicator {
    public Health health() {
        boolean ok = client.ping();
        return ok ? Health.up().build() : Health.down().withDetail("reason", "ping failed").build();
    }
}
```

```yaml
# Kubernetes probes
livenessProbe:
  httpGet: { path: /actuator/health/liveness, port: 8080 }
  initialDelaySeconds: 30
  failureThreshold: 3
readinessProbe:
  httpGet: { path: /actuator/health/readiness, port: 8080 }
  initialDelaySeconds: 10
  failureThreshold: 3
```

Liveness = app alive (restart if fails). Readiness = can accept traffic (include db, redis checks).

## Alerting Thresholds

| Metric | Condition | Severity |
|--------|----------|----------|
| P99 latency > 500ms | 5 min sustained | WARNING |
| P99 latency > 2s | 2 min sustained | CRITICAL |
| Error rate > 1% | 5 min sustained | WARNING |
| Error rate > 5% | 1 min sustained | CRITICAL |
| JVM heap > 85% | 10 min sustained | WARNING |
| DB pool saturation > 90% | Instant | CRITICAL |
| Health endpoint DOWN | Instant | CRITICAL |

## Rules

- Never log PII — mask emails, never log passwords/tokens/credentials.
- Always use SLF4J placeholders (`log.info("x={}", x)`) — never string concatenation.
- Always clear MDC in reactive `doFinally` blocks to prevent context leakage.
- Always set timeouts on health check external calls (2-5s) to prevent probe hangs.

## References

- **[references/logging.md](references/logging.md)** — Full Logback config (local + JSON), reactive MDC propagation, WebFilter correlation, sensitive data rules
- **[references/tracing-metrics.md](references/tracing-metrics.md)** — Dependencies, custom spans, Observation API, Micrometer auto-instrumentation, Prometheus alerts, reactive health indicators
- **[references/detailed-patterns.md](references/detailed-patterns.md)** — Legacy combined reference (all patterns in one file)

## Related Skills

- **spring-patterns** — WebFilter setup, production actuator defaults
- **pentest** — PII logging detection (OWASP A09)
- **testing-workflow** — Verification pipeline includes observability checks
