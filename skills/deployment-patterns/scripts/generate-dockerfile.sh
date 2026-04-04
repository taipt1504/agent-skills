#!/usr/bin/env bash
# =============================================================================
# generate-dockerfile.sh — Generate production Dockerfile for Spring Boot
# =============================================================================
# Detects Gradle/Maven, Java version, and generates multi-stage Dockerfile.
# Usage: bash generate-dockerfile.sh [project-dir]
# Output: Dockerfile content to stdout (redirect to save)
# =============================================================================
set -euo pipefail

PROJECT_DIR="${1:-.}"

# Detect build tool
BUILD_TOOL=""
if [ -f "$PROJECT_DIR/build.gradle.kts" ] || [ -f "$PROJECT_DIR/build.gradle" ]; then
  BUILD_TOOL="gradle"
elif [ -f "$PROJECT_DIR/pom.xml" ]; then
  BUILD_TOOL="maven"
else
  echo "ERROR: No build.gradle.kts, build.gradle, or pom.xml found in $PROJECT_DIR" >&2
  exit 1
fi

# Detect Java version
JAVA_VERSION="17"
if [ "$BUILD_TOOL" = "gradle" ]; then
  DETECTED=$(grep -oE 'sourceCompatibility\s*=\s*['\''"]?(\d+)' "$PROJECT_DIR"/build.gradle* 2>/dev/null | grep -oE '[0-9]+$' | head -1)
  [ -n "$DETECTED" ] && JAVA_VERSION="$DETECTED"
  DETECTED=$(grep -oE 'JavaLanguageVersion\.of\((\d+)\)' "$PROJECT_DIR"/build.gradle* 2>/dev/null | grep -oE '[0-9]+' | head -1)
  [ -n "$DETECTED" ] && JAVA_VERSION="$DETECTED"
elif [ "$BUILD_TOOL" = "maven" ]; then
  DETECTED=$(grep -oE '<java\.version>(\d+)</java\.version>' "$PROJECT_DIR/pom.xml" 2>/dev/null | grep -oE '[0-9]+' | head -1)
  [ -n "$DETECTED" ] && JAVA_VERSION="$DETECTED"
fi

# Detect service name
SERVICE_NAME=""
if [ "$BUILD_TOOL" = "gradle" ]; then
  SERVICE_NAME=$(grep -oE "rootProject\.name\s*=\s*['\"]([^'\"]+)" "$PROJECT_DIR/settings.gradle.kts" 2>/dev/null | sed "s/.*['\"]//")
  [ -z "$SERVICE_NAME" ] && SERVICE_NAME=$(grep -oE "rootProject\.name\s*=\s*['\"]([^'\"]+)" "$PROJECT_DIR/settings.gradle" 2>/dev/null | sed "s/.*['\"]//")
elif [ "$BUILD_TOOL" = "maven" ]; then
  SERVICE_NAME=$(grep -oP '<artifactId>\K[^<]+' "$PROJECT_DIR/pom.xml" | head -1)
fi
[ -z "$SERVICE_NAME" ] && SERVICE_NAME=$(basename "$(cd "$PROJECT_DIR" && pwd)")

# Detect exposed port
PORT="8080"
if [ -f "$PROJECT_DIR/src/main/resources/application.yml" ]; then
  DETECTED=$(grep -oE 'port:\s*(\d+)' "$PROJECT_DIR/src/main/resources/application.yml" | grep -oE '[0-9]+' | head -1)
  [ -n "$DETECTED" ] && PORT="$DETECTED"
fi

echo "# Auto-generated Dockerfile for $SERVICE_NAME"
echo "# Build tool: $BUILD_TOOL | Java: $JAVA_VERSION | Port: $PORT"
echo ""

if [ "$BUILD_TOOL" = "gradle" ]; then
  cat << DOCKERFILE
# Stage 1: Build
FROM eclipse-temurin:${JAVA_VERSION}-jdk-jammy AS builder
WORKDIR /app
COPY gradle/ gradle/
COPY gradlew build.gradle* settings.gradle* ./
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon || true
COPY src/ src/
RUN ./gradlew bootJar --no-daemon -x test

# Stage 2: Runtime
FROM eclipse-temurin:${JAVA_VERSION}-jre-jammy
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app

COPY --from=builder /app/build/libs/*.jar app.jar

USER appuser

ENV JAVA_OPTS="-XX:+UseContainerSupport \\
  -XX:MaxRAMPercentage=75.0 \\
  -XX:InitialRAMPercentage=50.0 \\
  -Djava.security.egd=file:/dev/./urandom"

EXPOSE ${PORT}

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \\
  CMD curl -f http://localhost:${PORT}/actuator/health/liveness || exit 1

ENTRYPOINT ["sh", "-c", "java \$JAVA_OPTS -jar app.jar"]
DOCKERFILE
else
  cat << DOCKERFILE
# Stage 1: Build
FROM eclipse-temurin:${JAVA_VERSION}-jdk-jammy AS builder
WORKDIR /app
COPY pom.xml mvnw ./
COPY .mvn/ .mvn/
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B || true
COPY src/ src/
RUN ./mvnw package -DskipTests -B

# Stage 2: Runtime
FROM eclipse-temurin:${JAVA_VERSION}-jre-jammy
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app

COPY --from=builder /app/target/*.jar app.jar

USER appuser

ENV JAVA_OPTS="-XX:+UseContainerSupport \\
  -XX:MaxRAMPercentage=75.0 \\
  -XX:InitialRAMPercentage=50.0 \\
  -Djava.security.egd=file:/dev/./urandom"

EXPOSE ${PORT}

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \\
  CMD curl -f http://localhost:${PORT}/actuator/health/liveness || exit 1

ENTRYPOINT ["sh", "-c", "java \$JAVA_OPTS -jar app.jar"]
DOCKERFILE
fi

echo ""
echo "# --- .dockerignore (create alongside Dockerfile) ---"
echo "# .git"
echo "# .gradle"
echo "# build/"
echo "# !build/libs/*.jar"
echo "# target/"
echo "# !target/*.jar"
echo "# *.md"
echo "# .idea"
echo "# .vscode"
