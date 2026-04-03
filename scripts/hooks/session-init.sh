#!/usr/bin/env bash
# =============================================================================
# session-init.sh — Session Start Hook (v3.1.1)
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
BRANCH=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
  BRANCH="$(git branch --show-current 2>/dev/null || echo "detached")"
  log "Git branch: $BRANCH"
fi

# --- Java version ---
JAVA_VERSION="$(java -version 2>&1 | head -1 | cut -d'"' -f2 2>/dev/null || echo "")"

# --- Java project version (from build config) ---
JAVA_PROJECT_VERSION=""
for gf in "$PROJECT_ROOT/build.gradle" "$PROJECT_ROOT/build.gradle.kts"; do
  if [ -f "$gf" ]; then
    ver=$(grep -oE "sourceCompatibility\s*=\s*['\"]?[0-9]+" "$gf" 2>/dev/null | grep -oE "[0-9]+" | head -1)
    [ -z "$ver" ] && ver=$(grep -oE "JavaVersion\.VERSION_([0-9]+)" "$gf" 2>/dev/null | grep -oE "[0-9]+" | head -1)
    [ -z "$ver" ] && ver=$(grep -oE "jvmTarget\s*=\s*['\"]?[0-9]+" "$gf" 2>/dev/null | grep -oE "[0-9]+" | head -1)
    [ -n "$ver" ] && JAVA_PROJECT_VERSION="$ver" && break
  fi
done
if [ -z "$JAVA_PROJECT_VERSION" ] && [ -f "$PROJECT_ROOT/gradle.properties" ]; then
  JAVA_PROJECT_VERSION=$(grep -oE "sourceCompatibility\s*=\s*[0-9]+" "$PROJECT_ROOT/gradle.properties" 2>/dev/null | grep -oE "[0-9]+" | head -1)
fi
if [ -z "$JAVA_PROJECT_VERSION" ] && [ -f "$PROJECT_ROOT/pom.xml" ]; then
  JAVA_PROJECT_VERSION=$(grep -oE "<maven\.compiler\.source>[0-9]+" "$PROJECT_ROOT/pom.xml" 2>/dev/null | grep -oE "[0-9]+" | head -1)
  [ -z "$JAVA_PROJECT_VERSION" ] && JAVA_PROJECT_VERSION=$(grep -oE "<java\.version>[0-9]+" "$PROJECT_ROOT/pom.xml" 2>/dev/null | grep -oE "[0-9]+" | head -1)
fi

# --- Write project profile (single source of truth for downstream hooks) ---
PROFILE_DIR="${PROJECT_ROOT}/.claude"
PROFILE_FILE="${PROFILE_DIR}/project-profile.json"
mkdir -p "$PROFILE_DIR" 2>/dev/null || true

SPRING_TYPE_SHORT=""
case "$SPRING_TYPE" in
  *WebFlux*) SPRING_TYPE_SHORT="WebFlux" ;;
  *MVC*|*Servlet*) SPRING_TYPE_SHORT="MVC" ;;
esac

cat > "$PROFILE_FILE" <<PROFILE_EOF
{
  "detectedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "projectName": "$PROJECT_NAME",
  "buildTool": "$BUILD_TOOL",
  "springType": $([ -n "$SPRING_TYPE_SHORT" ] && echo "\"$SPRING_TYPE_SHORT\"" || echo "null"),
  "summer": $SUMMER_DETECTED,
  "summerVersion": $([ -n "$SUMMER_VERSION" ] && echo "\"$SUMMER_VERSION\"" || echo "null"),
  "javaVersion": $([ -n "$JAVA_VERSION" ] && echo "\"$JAVA_VERSION\"" || echo "null"),
  "javaProjectVersion": $([ -n "$JAVA_PROJECT_VERSION" ] && echo "\"$JAVA_PROJECT_VERSION\"" || echo "null"),
  "branch": "$(printf '%s' "$BRANCH" | sed 's/"/\\"/g')"
}
PROFILE_EOF
log "Project profile written → $PROFILE_FILE"

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

# --- Summer active injection ---
if [ "$SUMMER_DETECTED" = true ]; then
  SUMMER_SKILL="${CLAUDE_PLUGIN_ROOT:-}/skills/summer-core/SKILL.md"
  [ ! -f "$SUMMER_SKILL" ] && SUMMER_SKILL="$(dirname "$0")/../../skills/summer-core/SKILL.md"
  if [ -f "$SUMMER_SKILL" ]; then
    SUMMER_CONTENT="$(cat "$SUMMER_SKILL" 2>/dev/null || true)"
    if [ -n "$SUMMER_CONTENT" ]; then
      SUMMER_ESC="$(echo "$SUMMER_CONTENT" | sed 's/\\/\\\\/g' | while IFS= read -r line; do printf '%s\\n' "$line"; done)"
      CONTEXT="${CONTEXT}## Summer Framework (ACTIVE — load summer skills for this project)\n\n${SUMMER_ESC}\n\n"
      log "Summer core skill injected ✓"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Project detection summary (compact, after bootstrap)
# ---------------------------------------------------------------------------
if [ -n "$SPRING_TYPE" ]; then
  [ -z "$JAVA_VERSION" ] && JAVA_VERSION="17+"
  CONTEXT="${CONTEXT}**Detected Stack**: Java ${JAVA_VERSION} · Spring Boot 3.x · $SPRING_TYPE"
  [ "$SUMMER_DETECTED" = true ] && CONTEXT="${CONTEXT} · Summer Framework${SUMMER_VERSION:+ v$SUMMER_VERSION}"
  CONTEXT="${CONTEXT}\n\n"
fi

[ -f "PROJECT_GUIDELINES.md" ] && CONTEXT="${CONTEXT}**Project guidelines**: \`PROJECT_GUIDELINES.md\` present — read it before starting work.\n\n"

# ---------------------------------------------------------------------------
# Config & Profile Injection (v3.1.1 — agents MUST receive config at runtime)
# ---------------------------------------------------------------------------
CONFIG_FILE="${PROJECT_ROOT}/.claude/devco-config.json"
PROFILE_FILE_INJ="${PROJECT_ROOT}/.claude/project-profile.json"

CONFIG_CTX=""

# Read devco-config.json
if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
  CONFIG_CTX=$(python3 -c "
import json, sys
try:
    c = json.load(open('$CONFIG_FILE'))
    mode = c.get('mode', 'standard')
    wf = c.get('workflow', {})
    team = c.get('team', {})
    proj = c.get('project', {})

    lines = []
    lines.append('## Plugin Configuration (from .claude/devco-config.json)')
    lines.append('')
    lines.append(f'**Mode**: {mode}')
    lines.append(f'**Workflow**: autoVerify={wf.get(\"autoVerify\", True)}, autoReview={wf.get(\"autoReview\", True)}, skipPlanConfirm={wf.get(\"skipPlanConfirm\", False)}, skipSpecConfirm={wf.get(\"skipSpecConfirm\", False)}')
    lines.append(f'**Limits**: maxRetryOnFail={wf.get(\"maxRetryOnFail\", 3)}, maxIterationsPerPhase={wf.get(\"maxIterationsPerPhase\", 10)}, noProgressThreshold={wf.get(\"noProgressThreshold\", 3)}')
    lines.append(f'**Team**: enabled={team.get(\"enabled\", False)}, maxTeammates={team.get(\"maxTeammates\", 4)}, spawnStrategy={team.get(\"spawnStrategy\", \"smart\")}')
    if team.get('enabled'):
        roles = team.get('roles', {})
        cost = team.get('costControl', {})
        lines.append(f'**Model Routing**: implementer={roles.get(\"implementer\",{}).get(\"model\",\"sonnet\")}, reviewer={roles.get(\"reviewer\",{}).get(\"model\",\"sonnet\")}')
        lines.append(f'**Cost Control**: preferFastModel={cost.get(\"preferFastModel\", True)}, useOpusOnlyFor={cost.get(\"useOpusOnlyFor\", [])}')
    lines.append(f'**Project**: type={proj.get(\"type\")}, useSummer={proj.get(\"useSummer\", False)}')
    print('\n'.join(lines))
except Exception as e:
    print(f'[SessionInit] WARNING: Could not read devco-config.json: {e}', file=sys.stderr)
" 2>/dev/null) || true
fi

# Read project-profile.json
PROFILE_CTX=""
if [ -f "$PROFILE_FILE_INJ" ] && command -v python3 &>/dev/null; then
  PROFILE_CTX=$(python3 -c "
import json, sys
try:
    p = json.load(open('$PROFILE_FILE_INJ'))
    lines = []
    lines.append('')
    lines.append('## Project Profile (from .claude/project-profile.json)')
    lines.append('')
    lines.append(f'**Build Tool**: {p.get(\"buildTool\", \"unknown\")}')
    lines.append(f'**Spring Type**: {p.get(\"springType\", \"unknown\")}')
    lines.append(f'**Summer Framework**: {p.get(\"summerFramework\", False)}')

    java_os = p.get('javaVersion', 'unknown')
    java_proj = p.get('javaProjectVersion', '')
    if java_proj:
        lines.append(f'**Java Version**: {java_proj} (project config) / {java_os} (OS runtime)')
    else:
        lines.append(f'**Java Version**: {java_os} (OS runtime — project version not detected)')

    deps = p.get('dependencies', {})
    active_deps = [k for k, v in deps.items() if v]
    if active_deps:
        lines.append(f'**Dependencies**: {\", \".join(active_deps)}')
    lines.append(f'**GitHub**: {p.get(\"github\", False)}')

    lines.append('')
    lines.append('### Skill Loading Hints (from profile)')
    spring_type = p.get('springType', 'unknown')
    if spring_type == 'webflux':
        lines.append('- Load **spring-patterns** (WebFlux mode — use Mono/Flux, StepVerifier, NEVER .block())')
    elif spring_type == 'mvc':
        lines.append('- Load **spring-patterns** (MVC mode — use RestTemplate, MockMvc, synchronous patterns)')
    if p.get('summerFramework'):
        lines.append('- Load **summer-core** + summer sub-skills (Summer Framework detected)')
    else:
        lines.append('- Do NOT load summer-* skills (Summer Framework not detected)')
    if deps.get('postgresql') or deps.get('mysql'):
        lines.append('- Load **database-patterns** (database dependency detected)')
    if deps.get('kafka') or deps.get('rabbitmq'):
        lines.append('- Load **messaging-patterns** (messaging dependency detected)')
    if deps.get('redis'):
        lines.append('- Load **redis-patterns** (Redis dependency detected)')

    print('\n'.join(lines))
except Exception as e:
    print(f'[SessionInit] WARNING: Could not read project-profile.json: {e}', file=sys.stderr)
" 2>/dev/null) || true
fi

# Output config context to session (stdout = agent context)
if [ -n "$CONFIG_CTX" ]; then
  CONTEXT="${CONTEXT}${CONFIG_CTX}\n\n"
fi
if [ -n "$PROFILE_CTX" ]; then
  CONTEXT="${CONTEXT}${PROFILE_CTX}\n\n"
fi

# Output
printf '%b' "$CONTEXT" 2>/dev/null || true

log "Session initialized ✓"
exit 0
