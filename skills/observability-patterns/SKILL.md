---
name: observability-patterns
description: Observability patterns for Java Spring Boot applications — structured logging with SLF4J/Logback, distributed tracing with Micrometer Tracing/OpenTelemetry, metrics with Micrometer/Prometheus, health checks, and alerting strategies. Use when setting up observability, debugging production issues, reviewing logging code, or designing monitoring for Spring Boot services.
---

# Observability Patterns for Spring Boot

Production-grade observability for Java 17+ / Spring Boot 3.x.

## Quick Reference

| Pillar | Tool Stack | Jump To |
|--------|-----------|---------|
| **Logs** | SLF4J + Logback + JSON | [Structured Logging](#structured-logging) |
| **Traces** | Micrometer Tracing + OTLP | [Distributed Tracing](#distributed-tracing) |
| **Metrics** | Micrometer + Prometheus | [Metrics & Alerting](#metrics--alerting) |
| **Health** | Spring Actuator | [Health Checks](#health-checks) |

---

## Dependencies

```xml
<!-- Micrometer + Prometheus -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>

<!-- Distributed Tracing (OTLP) -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>

<!-- Log correlation (adds traceId/spanId to log output) -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing</artifactId>
</dependency>
```

---

## Structured Logging

### Logback JSON Configuration

```xml
<!-- logback-spring.xml -->
<configuration>
    <springProfile name="!local">
        <!-- JSON output for production (Elasticsearch/Loki ingestion) -->
        <appender name="JSON_CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder class="net.logstash.logback.encoder.LogstashEncoder">
                <includeContext>false</includeContext>
                <customFields>{"service":"order-service","env":"${SPRING_PROFILES_ACTIVE}"}</customFields>
                <fieldNames>
                    <timestamp>@timestamp</timestamp>
                    <version>[ignore]</version>
                    <levelValue>[ignore]</levelValue>
                </fieldNames>
            </encoder>
        </appender>
        <root level="INFO">
            <appender-ref ref="JSON_CONSOLE"/>
        </root>
    </springProfile>

    <springProfile name="local">
        <!-- Readable output for local development -->
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
                <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} [%X{traceId}/%X{spanId}] - %msg%n</pattern>
            </encoder>
        </appender>
        <root level="DEBUG">
            <appender-ref ref="CONSOLE"/>
        </root>
    </springProfile>
</configuration>
```

### Logging Best Practices

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderService {

    // ─── CORRECT logging patterns ──────────────────────────────────────────────

    public Order create(CreateOrderCommand cmd) {
        // ✅ Structured context via MDC (auto-carried through reactive chains too)
        MDC.put("orderId", cmd.orderId());
        MDC.put("userId", cmd.userId());

        try {
            log.info("Creating order items={}", cmd.items().size());

            Order order = orderRepository.save(Order.from(cmd));

            // ✅ Use placeholders, not string concatenation
            log.info("Order created orderId={} totalAmount={}", order.id(), order.totalAmount());
            return order;

        } catch (Exception e) {
            // ✅ Log exception at point of failure, not rethrow silently
            log.error("Failed to create order userId={}", cmd.userId(), e);
            throw e;
        } finally {
            MDC.clear();
        }
    }

    // ❌ WRONG: Sensitive data in logs
    public void processPayment(PaymentRequest req) {
        log.info("Processing payment for card={}", req.cardNumber()); // NEVER log PII!
    }

    // ✅ CORRECT: Log identifiers only
    public void processPayment(PaymentRequest req) {
        log.info("Processing payment orderId={} last4={}", req.orderId(), req.last4());
    }
}
```

### Reactive Logging — MDC with Context Propagation

```java
// ✅ MDC context propagation for reactive chains
public Mono<Order> createReactive(CreateOrderCommand cmd) {
    return Mono.deferContextual(ctx -> {
        String traceId = ctx.getOrDefault("traceId", "none");
        MDC.put("traceId", traceId);
        MDC.put("orderId", cmd.orderId());

        return orderRepository.save(Order.from(cmd))
            .doOnNext(o -> log.info("Order created orderId={}", o.id()))
            .doOnError(e -> log.error("Order creation failed", e))
            .doFinally(sig -> MDC.clear());
    });
}

// ✅ Configure reactor context to log propagation
@Configuration
public class ReactorContextConfig {
    @Bean
    public ObservationRegistry observationRegistry() {
        ObservationRegistry registry = ObservationRegistry.create();
        // Auto-propagates traceId/spanId to MDC through reactive chains
        registry.observationConfig()
            .observationHandler(new DefaultMeterObservationHandler(meterRegistry));
        return registry;
    }
}
```

---

## Distributed Tracing

### Configuration

```yaml
# application.yml
management:
  tracing:
    sampling:
      probability: 1.0        # 100% in dev; use 0.1 (10%) in prod
    enabled: true

  otlp:
    tracing:
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://localhost:4318}/v1/traces
    metrics:
      export:
        step: 60s
        url: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://localhost:4318}/v1/metrics
```

### Custom Span Creation

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderEnrichmentService {

    private final Tracer tracer;
    private final ExternalInventoryClient inventoryClient;

    public Order enrich(Order order) {
        // ✅ Create custom span for meaningful operations
        Span span = tracer.nextSpan()
            .name("order.enrich")
            .tag("order.id", order.id())
            .tag("order.items.count", String.valueOf(order.items().size()))
            .start();

        try (Tracer.SpanInScope ws = tracer.withSpan(span)) {
            List<Product> products = inventoryClient.fetchProducts(
                order.items().stream().map(OrderItem::productId).toList());

            Order enriched = order.withProducts(products);
            span.tag("enrichment.status", "success");
            return enriched;

        } catch (Exception e) {
            span.tag("enrichment.status", "error");
            span.error(e);
            throw e;
        } finally {
            span.end();
        }
    }
}
```

### Propagating Correlation Headers

```java
// ✅ HttpClient with trace context propagation
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient webClient(ObservationRegistry observationRegistry) {
        return WebClient.builder()
            // Auto-propagates traceId/spanId as W3C Trace Context headers
            .observationRegistry(observationRegistry)
            .build();
    }
}

// ✅ RestTemplate (Spring MVC) with trace propagation
@Bean
public RestTemplate restTemplate(ObservationRegistry observationRegistry) {
    RestTemplate rt = new RestTemplate();
    rt.getInterceptors().add(new ObservationRestClientHttpRequestInterceptor(observationRegistry));
    return rt;
}
```

---

## Metrics & Alerting

### Custom Metrics

```java
@Service
@RequiredArgsConstructor
public class OrderMetricsService {

    private final MeterRegistry meterRegistry;

    // ─── Counters ────────────────────────────────────────────────────────────
    private final Counter ordersCreated;
    private final Counter ordersFailed;

    @PostConstruct
    public void initMetrics() {
        // Initialize counters once
        Counter.builder("orders.created.total")
            .description("Total orders created")
            .register(meterRegistry);

        Counter.builder("orders.failed.total")
            .description("Total order creation failures")
            .tag("reason", "validation")
            .register(meterRegistry);
    }

    // ─── Timers (latency histograms) ─────────────────────────────────────────
    public Order createWithMetrics(CreateOrderCommand cmd) {
        return Timer.builder("orders.creation.duration")
            .description("Order creation latency")
            .tag("status", "success")
            .register(meterRegistry)
            .record(() -> create(cmd));
    }

    // ─── Gauges (current value) ───────────────────────────────────────────────
    @PostConstruct
    public void registerQueueDepthGauge() {
        Gauge.builder("orders.pending.count", this, s -> s.countPendingOrders())
            .description("Current pending orders count")
            .register(meterRegistry);
    }

    // ─── Distribution Summary (value distributions) ───────────────────────────
    @PostConstruct
    public void registerOrderValueMetric() {
        DistributionSummary.builder("orders.value.amount")
            .description("Order value distribution")
            .baseUnit("USD cents")
            .publishPercentiles(0.5, 0.95, 0.99)
            .register(meterRegistry);
    }
}
```

### Spring Boot Auto-Instrumentation

```java
// ✅ @Timed on @RestController methods
@RestController
@Timed(value = "http.requests", extraTags = {"controller", "OrderController"})
public class OrderController { ... }

// ✅ @Observed for business method tracing
@Observed(name = "order.create", contextualName = "order-creation")
public Order create(CreateOrderCommand cmd) { ... }

// ✅ Database metrics — auto-configured when using Spring Data JPA
// Provides: jpa.repositories.*, spring.data.repository.*
```

### Prometheus Scrape Config

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus,env
      base-path: /actuator
  endpoint:
    health:
      show-details: when_authorized
      probes:
        enabled: true            # /actuator/health/liveness, /actuator/health/readiness
    prometheus:
      enabled: true
  metrics:
    export:
      prometheus:
        enabled: true
    distribution:
      percentiles-histogram:
        http.server.requests: true     # Enables latency histograms
      slo:
        http.server.requests: 50ms,200ms,500ms,1s  # SLO buckets
```

---

## Health Checks

### Custom Health Indicators

```java
// ✅ Custom health check for external dependencies
@Component
@RequiredArgsConstructor
public class ExternalInventoryHealthIndicator implements HealthIndicator {

    private final InventoryClient inventoryClient;

    @Override
    public Health health() {
        try {
            long start = System.currentTimeMillis();
            boolean healthy = inventoryClient.ping();
            long latency = System.currentTimeMillis() - start;

            if (healthy) {
                return Health.up()
                    .withDetail("latency_ms", latency)
                    .withDetail("endpoint", inventoryClient.getBaseUrl())
                    .build();
            } else {
                return Health.down()
                    .withDetail("reason", "ping returned false")
                    .build();
            }
        } catch (Exception e) {
            return Health.down()
                .withException(e)
                .build();
        }
    }
}

// ✅ Reactive health indicator for WebFlux
@Component
public class ReactiveRedisHealthIndicator implements ReactiveHealthIndicator {

    @Autowired
    private ReactiveRedisTemplate<String, String> redisTemplate;

    @Override
    public Mono<Health> health() {
        return redisTemplate.opsForValue().get("health-check")
            .map(val -> Health.up().withDetail("redis", "up").build())
            .onErrorReturn(Health.down().withDetail("redis", "connection failed").build());
    }
}
```

### Kubernetes Probes

```yaml
# application.yml — Kubernetes liveness/readiness
management:
  endpoint:
    health:
      probes:
        enabled: true
      group:
        liveness:
          include: livenessState      # App is alive (restart if fails)
        readiness:
          include: readinessState,db,redis  # App can accept traffic

# Kubernetes manifest
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
```

---

## Alerting Strategy

### Key Metrics to Alert On

| Metric | Alert Condition | Severity |
|--------|----------------|----------|
| `http.server.requests` P99 > 500ms | Sustained 5 min | WARNING |
| `http.server.requests` P99 > 2s | Sustained 2 min | CRITICAL |
| `http.server.requests` error rate > 1% | Sustained 5 min | WARNING |
| `http.server.requests` error rate > 5% | Sustained 1 min | CRITICAL |
| JVM heap usage > 85% | Sustained 10 min | WARNING |
| DB connection pool saturation > 90% | Instant | CRITICAL |
| Kafka consumer lag > 10,000 | Sustained 5 min | WARNING |
| Service health endpoint DOWN | Instant | CRITICAL |

### Prometheus Alert Rules (sample)

```yaml
# prometheus-rules.yml
groups:
  - name: order-service
    rules:
      - alert: HighErrorRate
        expr: |
          rate(http_server_requests_seconds_count{status=~"5..",job="order-service"}[5m])
          / rate(http_server_requests_seconds_count{job="order-service"}[5m]) > 0.05
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "High error rate: {{ $value | humanizePercentage }}"

      - alert: SlowResponseP99
        expr: |
          histogram_quantile(0.99,
            rate(http_server_requests_seconds_bucket{job="order-service"}[5m])) > 2
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "P99 latency {{ $value }}s exceeds 2s SLA"
```
