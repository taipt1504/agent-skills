# Distributed Tracing & Custom Metrics — Reference

## Dependencies

```groovy
implementation 'org.springframework.boot:spring-boot-starter-actuator'
implementation 'io.micrometer:micrometer-registry-prometheus'
implementation 'io.micrometer:micrometer-tracing-bridge-otel'
implementation 'io.opentelemetry:opentelemetry-exporter-otlp'
```

## Custom Span with Observation API

```java
@Service @RequiredArgsConstructor
public class OrderEnrichmentService {
    private final ObservationRegistry registry;

    public Mono<Order> enrich(Order order) {
        Observation observation = Observation.createNotStarted("order.enrich", registry)
            .lowCardinalityKeyValue("order.type", order.type().name())
            .start();
        return doEnrich(order)
            .doOnSuccess(o -> observation.stop())
            .doOnError(e -> { observation.error(e); observation.stop(); });
    }
}
```

## WebClient Trace Propagation

```java
WebClient client = WebClient.builder()
    .observationRegistry(registry)  // auto trace propagation
    .build();
```

## Micrometer Auto-Instrumentation

```java
@Configuration
public class ObservabilityConfig {
    @Bean
    public ObservedAspect observedAspect(ObservationRegistry registry) {
        return new ObservedAspect(registry);  // enables @Observed on any bean
    }
}
```

## Distribution Summary

```java
DistributionSummary summary = DistributionSummary.builder("order.amount")
    .baseUnit("usd")
    .publishPercentiles(0.5, 0.9, 0.95, 0.99)
    .publishPercentileHistogram()
    .serviceLevelObjectives(10, 50, 100, 500)
    .register(meterRegistry);
summary.record(order.amount().doubleValue());
```

## Reactive Health Indicator

```java
@Component
public class RedisHealthIndicator implements ReactiveHealthIndicator {
    private final ReactiveRedisTemplate<String, String> redis;
    @Override
    public Mono<Health> health() {
        return redis.opsForValue().get("health:ping")
            .map(v -> Health.up().withDetail("redis", "connected").build())
            .onErrorResume(e -> Mono.just(Health.down().withDetail("redis", e.getMessage()).build()))
            .timeout(Duration.ofSeconds(2),
                Mono.just(Health.down().withDetail("redis", "timeout").build()));
    }
}
```

## Prometheus Scrape Config

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'spring-boot'
    metrics_path: '/actuator/prometheus'
    scrape_interval: 15s
    static_configs:
      - targets: ['host.docker.internal:8080']
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
