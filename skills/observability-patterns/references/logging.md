# Structured Logging — Reference

> Read when: configuring logging infrastructure, log rotation, ELK/Loki pipelines, or structured JSON logging.

## Dependencies

```groovy
implementation 'net.logstash.logback:logstash-logback-encoder:7.4'
```

## Full Logback Configuration (logback-spring.xml)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <springProfile name="local">
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
                <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
            </encoder>
        </appender>
        <root level="INFO"><appender-ref ref="CONSOLE"/></root>
    </springProfile>

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
        <logger name="org.springframework.data.r2dbc" level="WARN"/>
        <logger name="io.netty" level="WARN"/>
        <logger name="reactor.netty" level="WARN"/>
    </springProfile>
</configuration>
```

## Reactive Context → MDC (Spring Boot 3.x)

```yaml
spring:
  reactor:
    context-propagation: auto  # auto MDC propagation
```

Use `Mono.deferContextual` only for custom MDC keys not covered by auto-propagation.

## WebFilter for Correlation Headers (WebFlux)

```java
@Component @Order(Ordered.HIGHEST_PRECEDENCE)
public class CorrelationWebFilter implements WebFilter {
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String traceId = exchange.getRequest().getHeaders().getFirst("X-Trace-Id");
        if (traceId == null) traceId = UUID.randomUUID().toString().substring(0, 8);
        exchange.getResponse().getHeaders().set("X-Trace-Id", traceId);
        String fid = traceId;
        return chain.filter(exchange).contextWrite(ctx -> ctx.put("traceId", fid));
    }
}
```

## MVC Filter Equivalent

```java
@Component @Order(Ordered.HIGHEST_PRECEDENCE)
public class CorrelationFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res,
                                     FilterChain chain) throws Exception {
        String traceId = req.getHeader("X-Trace-Id");
        if (traceId == null) traceId = UUID.randomUUID().toString().substring(0, 8);
        MDC.put("traceId", traceId);
        res.setHeader("X-Trace-Id", traceId);
        try {
            chain.doFilter(req, res);
        } finally {
            MDC.remove("traceId");
        }
    }
}
```

## Log Rotation (File-Based Environments)

For environments not using stdout-based collection:

```xml
<appender name="FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
    <file>/var/log/${SERVICE_NAME}/app.log</file>
    <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
        <fileNamePattern>/var/log/${SERVICE_NAME}/app.%d{yyyy-MM-dd}.%i.log.gz</fileNamePattern>
        <maxFileSize>100MB</maxFileSize>
        <maxHistory>30</maxHistory>
        <totalSizeCap>3GB</totalSizeCap>
    </rollingPolicy>
    <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
</appender>
```

## ELK Stack Integration

```
Spring Boot (JSON stdout) → Filebeat/Fluentd → Logstash → Elasticsearch → Kibana
```

### Filebeat Configuration

```yaml
filebeat.inputs:
  - type: container
    paths: ["/var/lib/docker/containers/*/*.log"]
    json.keys_under_root: true
    json.add_error_key: true

output.logstash:
  hosts: ["logstash:5044"]

processors:
  - add_kubernetes_metadata:
      host: ${NODE_NAME}
      matchers:
        - logs_path:
            logs_path: "/var/lib/docker/containers/"
```

### Logstash Pipeline

```ruby
input { beats { port => 5044 } }

filter {
  if [service] {
    mutate { add_field => { "[@metadata][index]" => "logs-%{service}" } }
  }
  date { match => ["timestamp", "ISO8601"] target => "@timestamp" }
  if [level] == "ERROR" {
    mutate { add_tag => ["alert_candidate"] }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "%{[@metadata][index]}-%{+YYYY.MM.dd}"
  }
}
```

## Loki + Grafana Integration (Lightweight Alternative)

```
Spring Boot (JSON stdout) → Promtail → Loki → Grafana
```

### Promtail Config

```yaml
scrape_configs:
  - job_name: kubernetes
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
    pipeline_stages:
      - json:
          expressions:
            level: level
            service: service
            traceId: traceId
      - labels:
          level:
          service:
      - timestamp:
          source: timestamp
          format: "2006-01-02T15:04:05.000Z"
```

### Grafana LogQL Queries

```
# All errors for order-service
{app="order-service"} |= "ERROR"

# Trace correlation
{app=~"order-service|payment-service"} | json | traceId="abc123"

# Error rate (last 5m)
sum(rate({app="order-service"} |= "ERROR" [5m]))
```

## Structured Logging Best Practices

### Log Levels

| Level | Use for | Example |
|-------|---------|---------|
| ERROR | Unexpected failures requiring action | DB connection failure, unhandled exception |
| WARN | Recoverable issues, degradation | Retry succeeded, circuit breaker open |
| INFO | Business events, state transitions | Order created, payment processed |
| DEBUG | Technical flow details | SQL query, cache hit/miss |
| TRACE | Fine-grained debugging | Request/response bodies (dev only) |

### Sensitive Data Rules

**Never log:** passwords, tokens, API keys, credit card numbers, SSN, full email (mask: `j***@example.com`), request bodies with credentials, full SQL parameter values.

**Always log:** request method + path + status + duration, business identifiers (orderId, userId), correlation IDs (traceId, spanId), error messages + stack traces.

### Request/Response Logging (WebFlux)

```java
@Slf4j
@Component @Order(Ordered.HIGHEST_PRECEDENCE + 1)
public class RequestLoggingFilter implements WebFilter {
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        long start = System.nanoTime();
        return chain.filter(exchange)
            .doFinally(signal -> {
                long duration = (System.nanoTime() - start) / 1_000_000;
                var req = exchange.getRequest();
                var status = exchange.getResponse().getStatusCode();
                log.info("HTTP {} {} → {} ({}ms)",
                    req.getMethod(), req.getPath(), status, duration);
            });
    }
}
```

### Request/Response Logging (MVC)

```java
@Slf4j
@Component
public class RequestLoggingInterceptor implements HandlerInterceptor {
    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res,
                              Object handler) {
        req.setAttribute("startTime", System.nanoTime());
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest req, HttpServletResponse res,
                                 Object handler, Exception ex) {
        long start = (long) req.getAttribute("startTime");
        long duration = (System.nanoTime() - start) / 1_000_000;
        log.info("HTTP {} {} → {} ({}ms)",
            req.getMethod(), req.getRequestURI(), res.getStatus(), duration);
    }
}
```
