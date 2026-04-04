# Health Probes & Graceful Shutdown — Reference

> Read when: configuring Spring Boot health endpoints, K8s probes, or graceful shutdown.

## Spring Boot Actuator Configuration

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true
      group:
        liveness:
          include: livenessState
        readiness:
          include: readinessState, db, redis
  health:
    livenessstate:
      enabled: true
    readinessstate:
      enabled: true

server:
  shutdown: graceful

spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

## Probe Semantics

| Probe | K8s Use | Endpoint | Failure Action |
|-------|---------|----------|----------------|
| **Liveness** | Pod restart | `/actuator/health/liveness` | Kill + restart pod |
| **Readiness** | Traffic routing | `/actuator/health/readiness` | Remove from Service |
| **Startup** | Init gate | `/actuator/health/liveness` | Wait until ready |

**Key rule:** Liveness checks app-internal state only (not external deps). Readiness checks external deps (DB, Redis, Kafka). If liveness checks DB and DB goes down, K8s restart-loops all pods pointlessly.

## Custom Health Indicators

### Reactive (WebFlux)

```java
@Component
public class KafkaHealthIndicator implements ReactiveHealthIndicator {
    private final KafkaTemplate<String, ?> kafka;

    @Override
    public Mono<Health> health() {
        return Mono.fromCallable(() -> {
            kafka.partitionsFor("health-check-topic");
            return Health.up().withDetail("kafka", "connected").build();
        }).onErrorResume(e ->
            Mono.just(Health.down(e).withDetail("kafka", "disconnected").build())
        );
    }
}
```

### Servlet (MVC)

```java
@Component
public class ExternalApiHealthIndicator implements HealthIndicator {
    private final RestClient restClient;

    @Override
    public Health health() {
        try {
            restClient.get().uri("/ping").retrieve().toBodilessEntity();
            return Health.up().withDetail("externalApi", "reachable").build();
        } catch (Exception e) {
            return Health.down(e).withDetail("externalApi", "unreachable").build();
        }
    }
}
```

### Composite Readiness (Multiple Deps)

```java
@Component
public class ReadinessHealthIndicator implements ReactiveHealthIndicator {
    private final DatabaseClient db;
    private final ReactiveRedisOperations<String, String> redis;

    @Override
    public Mono<Health> health() {
        Mono<Boolean> dbCheck = db.sql("SELECT 1").fetch().one()
            .map(r -> true).onErrorReturn(false);
        Mono<Boolean> redisCheck = redis.opsForValue().get("health-ping")
            .map(r -> true).onErrorReturn(true).defaultIfEmpty(true);

        return Mono.zip(dbCheck, redisCheck)
            .map(tuple -> {
                Health.Builder builder = tuple.getT1() && tuple.getT2()
                    ? Health.up() : Health.down();
                return builder
                    .withDetail("db", tuple.getT1() ? "up" : "down")
                    .withDetail("redis", tuple.getT2() ? "up" : "down")
                    .build();
            });
    }
}
```

## Graceful Shutdown Sequence

```
1. K8s sends SIGTERM
2. Pod marked as "Terminating" — removed from Service endpoints
3. Readiness probe starts failing → no new traffic
4. Spring receives shutdown signal
5. In-flight requests drain (up to timeout-per-shutdown-phase)
6. Kafka consumers commit offsets, stop polling
7. DB connection pool drains
8. Application exits
9. After terminationGracePeriodSeconds, K8s sends SIGKILL
```

**Critical timing rule:**
```
terminationGracePeriodSeconds > spring.lifecycle.timeout-per-shutdown-phase
         45s                >              30s
```

## Graceful Shutdown Checklist

1. `server.shutdown: graceful` in application.yml
2. `spring.lifecycle.timeout-per-shutdown-phase: 30s`
3. `terminationGracePeriodSeconds: 45` in K8s Deployment (> shutdown timeout)
4. Readiness probe fails first → K8s stops sending traffic
5. In-flight requests complete within timeout
6. Kafka consumers commit offsets before closing
7. Scheduled tasks stop accepting new work (`@PreDestroy`)
8. DB connection pool drains (HikariCP auto-handles)
9. WebSocket connections send close frame

## Environment Configuration

Use Spring profiles + ConfigMap/Secret:

```yaml
# application-kubernetes.yml
spring:
  r2dbc:
    url: ${DB_URL}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
  redis:
    host: ${REDIS_HOST:redis}
    port: ${REDIS_PORT:6379}
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP:kafka:9092}
```

Never hardcode secrets. Use K8s Secrets, SealedSecrets, or external vault (HashiCorp Vault, AWS Secrets Manager).
