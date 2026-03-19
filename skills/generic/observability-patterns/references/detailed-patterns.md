# Observability Patterns — Detailed Reference

## Dependencies

```groovy
// Micrometer + Prometheus
implementation 'org.springframework.boot:spring-boot-starter-actuator'
implementation 'io.micrometer:micrometer-registry-prometheus'

// OpenTelemetry Tracing
implementation 'io.micrometer:micrometer-tracing-bridge-otel'
implementation 'io.opentelemetry:opentelemetry-exporter-otlp'

// Structured Logging
implementation 'net.logstash.logback:logstash-logback-encoder:7.4'
```

## WebFilter for Correlation Headers (WebFlux)

```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class CorrelationWebFilter implements WebFilter {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String traceId = exchange.getRequest().getHeaders()
            .getFirst("X-Trace-Id");
        if (traceId == null) {
            traceId = UUID.randomUUID().toString().substring(0, 8);
        }

        exchange.getResponse().getHeaders().set("X-Trace-Id", traceId);

        String finalTraceId = traceId;
        return chain.filter(exchange)
            .contextWrite(ctx -> ctx.put("traceId", finalTraceId));
    }
}
```

## WebClient Trace Propagation

```java
@Bean
public WebClient tracedWebClient(WebClient.Builder builder,
                                  ObservationRegistry registry) {
    return builder
        .baseUrl("https://api.example.com")
        .observationRegistry(registry)
        .build();
}
```

## Custom Span with Tags

```java
@Service
@RequiredArgsConstructor
public class OrderEnrichmentService {

    private final Tracer tracer;

    public Mono<Order> enrich(Order order) {
        Observation observation = Observation.createNotStarted("order.enrich", registry)
            .lowCardinalityKeyValue("order.type", order.type().name())
            .start();

        return doEnrich(order)
            .doOnSuccess(o -> observation.stop())
            .doOnError(e -> {
                observation.error(e);
                observation.stop();
            });
    }
}
```

## Full Logback Configuration (logback-spring.xml)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <!-- Local: readable -->
    <springProfile name="local">
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
                <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
            </encoder>
        </appender>
        <root level="INFO"><appender-ref ref="CONSOLE"/></root>
    </springProfile>

    <!-- Production: JSON -->
    <springProfile name="!local">
        <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
            <encoder class="net.logstash.logback.encoder.LogstashEncoder">
                <customFields>{"service":"${SERVICE_NAME:-unknown}","env":"${SPRING_PROFILES_ACTIVE:-unknown}"}</customFields>
                <includeMdcKeyName>traceId</includeMdcKeyName>
                <includeMdcKeyName>orderId</includeMdcKeyName>
                <includeMdcKeyName>userId</includeMdcKeyName>
            </encoder>
        </appender>
        <root level="INFO"><appender-ref ref="JSON"/></root>

        <!-- Quiet noisy libraries -->
        <logger name="org.springframework.data.r2dbc" level="WARN"/>
        <logger name="io.netty" level="WARN"/>
        <logger name="reactor.netty" level="WARN"/>
    </springProfile>
</configuration>
```

## Reactive Context → MDC Propagation (Spring Boot 3.x)

```yaml
# application.yml — auto MDC propagation
spring:
  reactor:
    context-propagation: auto
```

```java
// Manual approach for custom keys
@Component
public class MdcContextLifter implements CoreSubscriber<Object> {
    // Spring Boot 3.x handles this automatically with context-propagation: auto
    // Only needed for pre-3.x or custom MDC keys not covered by auto-propagation
}
```

## Micrometer Auto-Instrumentation Decorators

```java
@Configuration
public class ObservabilityConfig {

    @Bean
    public ObservationRegistryCustomizer<ObservationRegistry> observationCustomizer() {
        return registry -> registry.observationConfig()
            .observationHandler(new DefaultMeterObservationHandler(meterRegistry));
    }

    // Auto-instrument all WebFlux handlers
    @Bean
    public ObservedAspect observedAspect(ObservationRegistry registry) {
        return new ObservedAspect(registry);
    }
}
```

## Distribution Summary (Detailed Histograms)

```java
DistributionSummary summary = DistributionSummary.builder("order.amount")
    .baseUnit("usd")
    .publishPercentiles(0.5, 0.9, 0.95, 0.99)
    .publishPercentileHistogram()
    .serviceLevelObjectives(10, 50, 100, 500)
    .register(meterRegistry);

summary.record(order.amount().doubleValue());
```

## Prometheus Alert Rules

```yaml
groups:
  - name: service-alerts
    rules:
      - alert: HighLatency
        expr: histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m])) > 0.5
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "P99 latency > 500ms for {{ $labels.uri }}"

      - alert: CriticalLatency
        expr: histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[2m])) > 2
        for: 2m
        labels: { severity: critical }

      - alert: HighErrorRate
        expr: rate(http_server_requests_seconds_count{status=~"5.."}[5m]) / rate(http_server_requests_seconds_count[5m]) > 0.01
        for: 5m
        labels: { severity: warning }

      - alert: CriticalErrorRate
        expr: rate(http_server_requests_seconds_count{status=~"5.."}[1m]) / rate(http_server_requests_seconds_count[1m]) > 0.05
        for: 1m
        labels: { severity: critical }

      - alert: JvmHeapHigh
        expr: jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"} > 0.85
        for: 10m
        labels: { severity: warning }

      - alert: DbPoolSaturated
        expr: hikaricp_connections_active / hikaricp_connections_max > 0.9
        labels: { severity: critical }
```

## Custom Health Indicator (Reactive)

```java
@Component
public class RedisHealthIndicator implements ReactiveHealthIndicator {

    private final ReactiveRedisTemplate<String, String> redis;

    @Override
    public Mono<Health> health() {
        return redis.opsForValue()
            .get("health:ping")
            .map(v -> Health.up().withDetail("redis", "connected").build())
            .onErrorResume(e -> Mono.just(
                Health.down().withDetail("redis", e.getMessage()).build()))
            .timeout(Duration.ofSeconds(2),
                Mono.just(Health.down().withDetail("redis", "timeout").build()));
    }
}
```

## Prometheus Scrape Config (docker-compose)

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'spring-boot'
    metrics_path: '/actuator/prometheus'
    scrape_interval: 15s
    static_configs:
      - targets: ['host.docker.internal:8080']
```

## Sensitive Data Rules

Never log:
- Passwords, tokens, API keys, secrets
- Credit card numbers, SSN, government IDs
- Full email addresses (mask: `j***@example.com`)
- Request bodies containing credentials
- Full SQL queries with parameter values (log parameterized form only)

Always log:
- Request method + path + status code + duration
- Business event identifiers (orderId, userId — not PII)
- Error messages (without stack traces in production JSON)
- Correlation IDs (traceId, spanId)
