# Structured Logging — Reference

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

## Sensitive Data Rules

**Never log:** passwords, tokens, API keys, credit card numbers, SSN, full email (mask: `j***@example.com`), request bodies with credentials, full SQL with parameter values.

**Always log:** request method + path + status + duration, business identifiers (orderId, userId), correlation IDs (traceId, spanId), error messages.
