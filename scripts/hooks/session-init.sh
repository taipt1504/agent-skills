#!/usr/bin/env bash
# =============================================================================
# session-init.sh — Session Start Hook (v3.0)
# =============================================================================
# Detects project type, restores L2 memory, injects bootstrap skill.
# Replaces: session-start.sh
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "session-init" || exit 0

log() { echo "[SessionInit] $*" >&2; }
safe() { "$@" 2>/dev/null || true; }

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true
PROJECT_NAME="$(basename "$(pwd)")"

log "Project: $PROJECT_NAME | Root: $PROJECT_ROOT"

# --- Auto-init memory ---
MEMORY_INIT="$(dirname "$0")/../memory/init.sh"
[ -x "$MEMORY_INIT" ] || MEMORY_INIT="${CLAUDE_PLUGIN_ROOT:-}/scripts/memory/init.sh"
if [ -x "$MEMORY_INIT" ]; then
  bash "$MEMORY_INIT" "$PROJECT_ROOT" 2>/dev/null || true
fi

# --- Detect project type ---
BUILD_TOOL="unknown"
if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  [ -f "gradlew" ] && BUILD_TOOL="Gradle Wrapper (./gradlew)" || BUILD_TOOL="Gradle"
elif [ -f "pom.xml" ]; then
  [ -f "mvnw" ] && BUILD_TOOL="Maven Wrapper (./mvnw)" || BUILD_TOOL="Maven"
fi
[ "$BUILD_TOOL" != "unknown" ] && log "Build tool: $BUILD_TOOL"

# --- Spring type detection ---
SPRING_TYPE=""
GRADLE_FILE=""
[ -f "build.gradle" ] && GRADLE_FILE="build.gradle"
[ -f "build.gradle.kts" ] && GRADLE_FILE="build.gradle.kts"

if [ -n "$GRADLE_FILE" ]; then
  grep -q "spring-boot-starter-webflux" "$GRADLE_FILE" 2>/dev/null && SPRING_TYPE="WebFlux (Reactive)"
  [ -z "$SPRING_TYPE" ] && grep -q "spring-boot-starter-web" "$GRADLE_FILE" 2>/dev/null && SPRING_TYPE="Spring MVC (Servlet)"
elif [ -f "pom.xml" ]; then
  grep -q "spring-boot-starter-webflux" pom.xml 2>/dev/null && SPRING_TYPE="WebFlux (Reactive)"
  [ -z "$SPRING_TYPE" ] && grep -q "spring-boot-starter-web" pom.xml 2>/dev/null && SPRING_TYPE="Spring MVC (Servlet)"
fi
[ -n "$SPRING_TYPE" ] && log "Spring type: $SPRING_TYPE"

# --- Summer Framework detection ---
SUMMER_DETECTED=false
SUMMER_VERSION=""
BUILD_SRC="${GRADLE_FILE:-pom.xml}"
if [ -n "$BUILD_SRC" ] && [ -f "$BUILD_SRC" ]; then
  if grep -q "io.f8a.summer" "$BUILD_SRC" 2>/dev/null; then
    SUMMER_DETECTED=true
    # Try to get version from gradle.properties
    if [ -f "gradle.properties" ]; then
      SUMMER_VERSION="$(grep -oE 'summerVersion\s*=\s*[0-9.]+' gradle.properties 2>/dev/null | grep -oE '[0-9.]+' || echo "")"
    fi
    log "Summer Framework: detected${SUMMER_VERSION:+ (v$SUMMER_VERSION)}"
  fi
fi

# --- Git context ---
if git rev-parse --is-inside-work-tree &>/dev/null; then
  BRANCH="$(git branch --show-current 2>/dev/null || echo "detached")"
  log "Git branch: $BRANCH"
fi

# --- Build context output ---
CONTEXT=""

# ---------------------------------------------------------------------------
# BOOTSTRAP SKILL INJECTION (CRITICAL — this is the enforcement engine)
# ---------------------------------------------------------------------------
# Resolve bootstrap skill path: plugin cache or local
BOOTSTRAP_SKILL="${CLAUDE_PLUGIN_ROOT:-}/skills/bootstrap/SKILL.md"
if [ ! -f "$BOOTSTRAP_SKILL" ]; then
  # Fallback: look relative to this script
  BOOTSTRAP_SKILL="$(dirname "$0")/../../skills/bootstrap/SKILL.md"
fi

if [ -f "$BOOTSTRAP_SKILL" ]; then
  BOOTSTRAP_CONTENT="$(cat "$BOOTSTRAP_SKILL" 2>/dev/null || true)"
  if [ -n "$BOOTSTRAP_CONTENT" ]; then
    CONTEXT="EXTREMELY IMPORTANT — READ AND INTERNALIZE THIS ENTIRE SECTION:\n\n"
    # Escape backslashes and preserve content for printf %b
    BOOTSTRAP_ESC="$(echo "$BOOTSTRAP_CONTENT" | sed 's/\\/\\\\/g' | while IFS= read -r line; do printf '%s\\n' "$line"; done)"
    CONTEXT="${CONTEXT}${BOOTSTRAP_ESC}\n\n"
    log "Bootstrap skill injected ✓"
  fi
else
  log "WARNING: Bootstrap skill not found at $BOOTSTRAP_SKILL"
  # Fallback: inject minimal workflow reminder
  CONTEXT="## Workflow\n\n"
  CONTEXT="${CONTEXT}**Trivial** (≤5 lines, 1 file, no new behavior) → BUILD directly\n"
  CONTEXT="${CONTEXT}**Non-trivial** → \`/plan\` → confirm → \`/spec\` → approve → BUILD (TDD: RED→GREEN→REFACTOR)\n\n"
  CONTEXT="${CONTEXT}**Hard blocks**: No code without /plan+/spec approval · Tests first · No .block() in src/main/ · No git commit\n\n"
fi

# ---------------------------------------------------------------------------
# L2 memory context
# ---------------------------------------------------------------------------
READ_CONTEXT="$(dirname "$0")/../memory/read-context.sh"
[ -x "$READ_CONTEXT" ] || READ_CONTEXT="${CLAUDE_PLUGIN_ROOT:-}/scripts/memory/read-context.sh"
if [ -x "$READ_CONTEXT" ]; then
  MEMORY_CONTEXT="$(bash "$READ_CONTEXT" 2>/dev/null || true)"
  [ -n "$MEMORY_CONTEXT" ] && CONTEXT="${CONTEXT}## Memory Context\n\n${MEMORY_CONTEXT}\n\n"
fi

# ---------------------------------------------------------------------------
# Project detection summary (compact, after bootstrap)
# ---------------------------------------------------------------------------
if [ -n "$SPRING_TYPE" ]; then
  JAVA_VERSION="$(java -version 2>&1 | head -1 | cut -d'"' -f2 2>/dev/null || echo "17+")"
  CONTEXT="${CONTEXT}**Detected Stack**: Java ${JAVA_VERSION} · Spring Boot 3.x · $SPRING_TYPE"
  [ "$SUMMER_DETECTED" = true ] && CONTEXT="${CONTEXT} · Summer Framework${SUMMER_VERSION:+ v$SUMMER_VERSION}"
  CONTEXT="${CONTEXT}\n\n"
fi

[ -f "PROJECT_GUIDELINES.md" ] && CONTEXT="${CONTEXT}**Project guidelines**: \`PROJECT_GUIDELINES.md\` present — read it before starting work.\n\n"

# Output
printf '%b' "$CONTEXT" 2>/dev/null || true

log "Session initialized ✓"
exit 0
