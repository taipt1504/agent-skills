---
name: deployment-patterns
description: >
  Deployment patterns for Java Spring Boot — Docker, Kubernetes, CI/CD, health probes, graceful
  shutdown. Use when writing Dockerfiles, K8s manifests (Deployment/Service/HPA/ConfigMap),
  CI/CD pipelines (GitHub Actions, GitLab CI), configuring health probes (liveness/readiness/startup),
  setting up graceful shutdown, sizing container resources, or containerizing Spring Boot applications.
triggers:
  natural: ["dockerfile", "kubernetes", "k8s", "ci/cd", "deploy", "health check", "container", "graceful shutdown", "docker image", "helm"]
  code: ["Dockerfile", "deployment.yaml", "health", "actuator", "HorizontalPodAutoscaler"]
requires: []
applicability:
  always: false
  triggers:
    files_match: ["**/application*.yml", "**/application*.properties", "**/Dockerfile", "**/docker-compose.yml", "**/build.gradle*", "**/pom.xml", ".github/workflows/**"]
    code_patterns: ["@Profile", "@ConditionalOn", "spring.profiles", "ENV "]
    task_keywords: ["deployment", "profile", "config", "Docker", "Kubernetes", "graceful shutdown", "actuator", "production"]
    related_rules:
      - rules/java/observability.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 80%+: new profile, deploy target, container/orchestration config
  MEDIUM 40-79%: app config tweak (timeouts, pool sizes, actuator endpoints)
  LOW 1-39%: dependency version bump
  ZERO: no infrastructure / config files touched
---

# Deployment Patterns — Docker, K8s, CI/CD

## Quick Decision Matrix

| Need | Reference | When to read |
|------|-----------|-------------|
| Dockerfile | `references/dockerfile.md` | Creating/reviewing Docker images |
| K8s manifests | `references/kubernetes.md` | Writing Deployment, Service, HPA, ConfigMap |
| CI/CD pipeline | `references/cicd.md` | Setting up GitHub Actions or GitLab CI |
| Health probes | `references/health-probes.md` | Configuring liveness/readiness/startup probes |
| Generate Dockerfile | `scripts/generate-dockerfile.sh` | Scaffold a production Dockerfile |

## Core Principles

1. **Separate build/runtime** — multi-stage builds (JDK build, JRE runtime)
2. **Never root** — `USER appuser` in production images
3. **Container-aware JVM** — `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`
4. **Probe semantics** — liveness = internal only, readiness = external deps
5. **Graceful shutdown** — `terminationGracePeriodSeconds` > `timeout-per-shutdown-phase`
6. **No secrets in images** — K8s Secrets, SealedSecrets, or Vault

## Dockerfile Essentials

```dockerfile
# Build
FROM eclipse-temurin:17-jdk-jammy AS builder
WORKDIR /app
COPY gradle/ gradle/
COPY gradlew build.gradle.kts settings.gradle.kts ./
RUN ./gradlew dependencies --no-daemon || true
COPY src/ src/
RUN ./gradlew bootJar --no-daemon -x test

# Runtime
FROM eclipse-temurin:17-jre-jammy
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
USER appuser
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0"
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

Layered JAR, Maven, JVM flags → `references/dockerfile.md`.

## Health Probes Summary

```yaml
# application.yml
management:
  endpoint.health:
    probes.enabled: true
    group:
      liveness:
        include: livenessState
      readiness:
        include: readinessState, db, redis
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

| Probe | Endpoint | Checks | Failure → |
|-------|----------|--------|-----------|
| Liveness | `/actuator/health/liveness` | App alive | Pod restart |
| Readiness | `/actuator/health/readiness` | DB, Redis | Remove from Service |
| Startup | `/actuator/health/liveness` | Init done | Wait |

Custom HealthIndicators, composite readiness, shutdown sequence → `references/health-probes.md`.

## Resource Sizing

| Type | Mem Request | Mem Limit | CPU Request | CPU Limit |
|------|-----------|-----------|------------|----------|
| Lightweight API | 256Mi | 512Mi | 100m | 500m |
| Standard API | 512Mi | 1Gi | 250m | 1000m |
| Heavy Processing | 1Gi | 2Gi | 500m | 2000m |

Full K8s manifests (Deployment, Service, HPA, ConfigMap, NetworkPolicy) → `references/kubernetes.md`.

## CI/CD Pipeline Quick Reference

Stages: build & test → security scan → Docker build + Trivy scan → deploy staging → deploy production. Full YAML, strategies → `references/cicd.md`.

## Graceful Shutdown Checklist

1. `server.shutdown: graceful`
2. `spring.lifecycle.timeout-per-shutdown-phase: 30s`
3. `terminationGracePeriodSeconds: 45` (must be > shutdown timeout)
4. Readiness probe fails first → K8s stops new traffic
5. In-flight requests drain within timeout
6. Kafka consumers commit offsets, DB pool drains

## Related Skills

- **observability-patterns** — Prometheus metrics, structured logging, tracing
- **spring-webflux-patterns** — Spring Boot configuration, profiles
- **architecture** — Hexagonal structure mapping to Docker layers
