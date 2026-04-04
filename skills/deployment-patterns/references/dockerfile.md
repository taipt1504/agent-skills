# Multi-Stage Dockerfile — Reference

> Read when: creating or reviewing Dockerfiles for Spring Boot services.

## Standard Multi-Stage (Gradle)

```dockerfile
# Stage 1: Build
FROM eclipse-temurin:17-jdk-jammy AS builder
WORKDIR /app
COPY gradle/ gradle/
COPY gradlew build.gradle.kts settings.gradle.kts ./
RUN ./gradlew dependencies --no-daemon || true
COPY src/ src/
RUN ./gradlew bootJar --no-daemon -x test

# Stage 2: Runtime
FROM eclipse-temurin:17-jre-jammy
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app

COPY --from=builder /app/build/libs/*.jar app.jar

USER appuser

ENV JAVA_OPTS="-XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -XX:InitialRAMPercentage=50.0 \
  -Djava.security.egd=file:/dev/./urandom"

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health/liveness || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

## Maven Variant

```dockerfile
FROM eclipse-temurin:17-jdk-jammy AS builder
WORKDIR /app
COPY pom.xml mvnw ./
COPY .mvn/ .mvn/
RUN ./mvnw dependency:go-offline -B || true
COPY src/ src/
RUN ./mvnw package -DskipTests -B

FROM eclipse-temurin:17-jre-jammy
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
USER appuser
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

## Layered JAR (Spring Boot 3.x)

For faster rebuilds using Spring Boot's layered JAR feature:

```dockerfile
FROM eclipse-temurin:17-jdk-jammy AS builder
WORKDIR /app
COPY . .
RUN ./gradlew bootJar --no-daemon -x test
RUN java -Djarmode=layertools -jar build/libs/*.jar extract --destination extracted

FROM eclipse-temurin:17-jre-jammy
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app

COPY --from=builder /app/extracted/dependencies/ ./
COPY --from=builder /app/extracted/spring-boot-loader/ ./
COPY --from=builder /app/extracted/snapshot-dependencies/ ./
COPY --from=builder /app/extracted/application/ ./

USER appuser
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]
```

## Key JVM Container Flags

| Flag | Purpose | Recommended |
|------|---------|-------------|
| `-XX:+UseContainerSupport` | Detect cgroup memory/cpu limits | Always on (default JDK 11+) |
| `-XX:MaxRAMPercentage=75.0` | Heap as % of container memory | 70-80% for typical services |
| `-XX:InitialRAMPercentage=50.0` | Initial heap allocation | 50% for faster warmup |
| `-Djava.security.egd=file:/dev/./urandom` | Faster SecureRandom init | Always in containers |
| `-XX:+UseG1GC` | GC for balanced throughput/latency | Default JDK 17 |
| `-XX:+UseZGC` | Ultra-low pause GC | High-memory services (>4GB) |

## .dockerignore

```
.git
.gradle
build/
!build/libs/*.jar
*.md
.idea
.vscode
```

## Security Checklist

1. Never run as root — always `USER appuser`
2. Use `-jre-` base image, not `-jdk-` for runtime
3. Pin base image tags (e.g., `17-jre-jammy` not `latest`)
4. No secrets in ENV or build args
5. Multi-stage build keeps build tools out of runtime image
6. Scan with `trivy image` or `grype` before push
