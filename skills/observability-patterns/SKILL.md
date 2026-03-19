---
name: observability-patterns
description: >
  Observability patterns for Spring Boot — structured logging, distributed tracing,
  custom metrics, health indicators, Kubernetes probes, and alerting strategies.
triggers:
  - logging config
  - Logback
  - Micrometer
  - tracing
  - metrics
  - health checks
  - alerting
  - Prometheus
---

# Observability Patterns for Spring Boot

## When to Activate

- Setting up logging, metrics, or tracing for a service
- Debugging production issues
- Reviewing logging code or monitoring configuration
- Designing alerting and health checks

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

## References

- **[references/detailed-patterns.md](references/detailed-patterns.md)** — Full code: dependencies, WebFilter correlation, WebClient tracing, custom spans, Logback config (local + JSON), reactive MDC propagation, Micrometer auto-instrumentation, distribution summaries, Prometheus alert rules, reactive health indicators, scrape config, sensitive data rules
