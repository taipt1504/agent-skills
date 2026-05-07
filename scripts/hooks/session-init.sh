#!/usr/bin/env bash
# =============================================================================
# session-init.sh — Session Start Hook
# =============================================================================
# Detects project type, restores L2 memory, injects bootstrap skill.
# Replaces: session-start.sh
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "session-init" || exit 0

log() { echo "[SessionInit] $*" >&2; }
warn() { echo "[SessionInit] ⚠️  $*" >&2; }
safe() { "$@" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Manifest validation (R4) — detect malformed hooks.json early, fail loudly.
# Without this, a corrupted hooks.json silently breaks plugin enforcement
# and Claude Code burns budget retrying without a clear error.
# ---------------------------------------------------------------------------
HOOKS_JSON="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/../..}/hooks/hooks.json"
if [ -f "$HOOKS_JSON" ] && command -v python3 &>/dev/null; then
  if ! python3 -c "import json; json.load(open('$HOOKS_JSON'))" 2>/dev/null; then
    warn "hooks.json is malformed JSON ($HOOKS_JSON). Run: bash scripts/ci/validate-hooks.sh"
    warn "Plugin hooks may not be loaded for this session. Skill enforcement disabled."
    # Continue session; let Claude Code start without crashing.
  fi
fi

# ---------------------------------------------------------------------------
# Required hook script presence check (R5) — warn if any wired hook script
# is missing. Silent-skip is the Claude Code default but loses enforcement.
# ---------------------------------------------------------------------------
HOOKS_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/../..}/scripts/hooks"
REQUIRED_HOOKS="session-init.sh subagent-init.sh workflow-gate.sh skill-router.sh \
                compact-advisor.sh git-guard.sh quality-gate.sh build-checkpoint.sh \
                memory-gate.sh workflow-phase-lock.sh workflow-tracker.sh \
                verify-fix-loop.sh team-spawn-evaluator.sh observability-trace.sh \
                pre-compact.sh post-compact.sh session-save.sh run-with-flags.sh"
for h in $REQUIRED_HOOKS; do
  if [ ! -f "$HOOKS_DIR/$h" ]; then
    warn "missing hook script: $HOOKS_DIR/$h — enforcement may be partial"
  fi
done

# ---------------------------------------------------------------------------
# Project root detection (R7) — walk up from CWD to find nearest build file.
# Falls back to git root, then PWD. Fixes monorepo subdirectory case where
# `git rev-parse --show-toplevel` returns the monorepo root instead of the
# active subproject.
# ---------------------------------------------------------------------------
_find_project_root() {
  local d="$PWD"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -f "$d/build.gradle" ] || [ -f "$d/build.gradle.kts" ] || [ -f "$d/pom.xml" ]; then
      echo "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}
PROJECT_ROOT="$(_find_project_root)" || PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
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
    # Fallback: scan build file for inline version declaration
    if [ -z "$SUMMER_VERSION" ] && [ -n "$GRADLE_FILE" ]; then
      SUMMER_VERSION="$(grep -oE 'io\.f8a\.summer:summer-platform:[0-9]+\.[0-9]+\.[0-9]+' "$GRADLE_FILE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")"
      [ -z "$SUMMER_VERSION" ] && SUMMER_VERSION="$(grep -oE 'io\.f8a\.summer:summer-platform:[0-9]+\.[0-9]+\.[0-9]+' "$GRADLE_FILE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")"
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
# Fallback: toolchain languageVersion (may span multiple lines — use tr to flatten)
if [ -z "$JAVA_PROJECT_VERSION" ] && [ -n "$GRADLE_FILE" ]; then
  JAVA_PROJECT_VERSION=$(tr '\n' ' ' < "$GRADLE_FILE" 2>/dev/null \
    | grep -oE 'toolchain\s*\{[^}]*languageVersion[^}]*\}' \
    | grep -oE 'JavaLanguageVersion\.of\(([0-9]+)\)' \
    | grep -oE '[0-9]+' | head -1 || echo "")
fi

# --- Dependency detection ---
DEP_POSTGRESQL=false
DEP_MYSQL=false
DEP_REDIS=false
DEP_KAFKA=false
DEP_RABBITMQ=false
DEP_DOCKER=false

_scan_dep() {
  local pattern="$1"
  local build_src="${GRADLE_FILE:-}"
  [ -z "$build_src" ] && [ -f "pom.xml" ] && build_src="pom.xml"
  [ -n "$build_src" ] && grep -qi "$pattern" "$build_src" 2>/dev/null
}

{ _scan_dep "postgresql" || _scan_dep "r2dbc-postgresql"; } && DEP_POSTGRESQL=true || true
{ _scan_dep "mysql" || _scan_dep "r2dbc-mysql"; } && DEP_MYSQL=true || true
{ _scan_dep "redis" || _scan_dep "lettuce"; } && DEP_REDIS=true || true
_scan_dep "kafka" && DEP_KAFKA=true || true
{ _scan_dep "rabbitmq" || _scan_dep "amqp"; } && DEP_RABBITMQ=true || true
{ _scan_dep "testcontainers" || _scan_dep "docker"; } && DEP_DOCKER=true || true

# --- Write project profile (single source of truth for downstream hooks) ---
PROFILE_DIR="${PROJECT_ROOT}/.claude"
PROFILE_FILE="${PROFILE_DIR}/project-profile.json"
mkdir -p "$PROFILE_DIR" 2>/dev/null || true
mkdir -p "${PROFILE_DIR}/memory/context" 2>/dev/null || true
mkdir -p "${PROFILE_DIR}/sessions" 2>/dev/null || true

SPRING_TYPE_SHORT=""
case "$SPRING_TYPE" in
  *WebFlux*) SPRING_TYPE_SHORT="WebFlux" ;;
  *MVC*|*Servlet*) SPRING_TYPE_SHORT="MVC" ;;
esac

# --- Merge with existing profile (preserve non-null user-provided values) ---
_EXISTING_SPRING_TYPE=""
_EXISTING_SUMMER_VERSION=""
_EXISTING_JAVA_VERSION=""
_EXISTING_JAVA_PROJECT_VERSION=""
if [ -f "$PROFILE_FILE" ] && command -v python3 &>/dev/null; then
  _merge_result=$(python3 -c "
import json, sys
try:
    p = json.load(open('$PROFILE_FILE'))
    # Return pipe-delimited non-null preserved values
    st   = p.get('springType') or ''
    sv   = p.get('summerVersion') or ''
    jv   = p.get('javaVersion') or ''
    jpv  = p.get('javaProjectVersion') or ''
    print(f'{st}|{sv}|{jv}|{jpv}')
except Exception:
    print('|||')
" 2>/dev/null) || _merge_result="|||"
  _EXISTING_SPRING_TYPE="${_merge_result%%|*}"
  _rest="${_merge_result#*|}"
  _EXISTING_SUMMER_VERSION="${_rest%%|*}"
  _rest="${_rest#*|}"
  _EXISTING_JAVA_VERSION="${_rest%%|*}"
  _EXISTING_JAVA_PROJECT_VERSION="${_rest#*|}"
fi

# Only overwrite null values with newly detected values; prefer existing if already set
[ -z "$SPRING_TYPE_SHORT" ] && [ -n "$_EXISTING_SPRING_TYPE" ] && SPRING_TYPE_SHORT="$_EXISTING_SPRING_TYPE"
[ -z "$SUMMER_VERSION" ]    && [ -n "$_EXISTING_SUMMER_VERSION" ] && SUMMER_VERSION="$_EXISTING_SUMMER_VERSION"
[ -z "$JAVA_VERSION" ]      && [ -n "$_EXISTING_JAVA_VERSION" ] && JAVA_VERSION="$_EXISTING_JAVA_VERSION"
[ -z "$JAVA_PROJECT_VERSION" ] && [ -n "$_EXISTING_JAVA_PROJECT_VERSION" ] && JAVA_PROJECT_VERSION="$_EXISTING_JAVA_PROJECT_VERSION"

cat > "$PROFILE_FILE" <<PROFILE_EOF
{
  "\$schema": "../config/project-profile.schema.json",
  "detectedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "projectName": "$PROJECT_NAME",
  "buildTool": "$BUILD_TOOL",
  "springType": $([ -n "$SPRING_TYPE_SHORT" ] && echo "\"$SPRING_TYPE_SHORT\"" || echo "null"),
  "summer": $SUMMER_DETECTED,
  "summerVersion": $([ -n "$SUMMER_VERSION" ] && echo "\"$SUMMER_VERSION\"" || echo "null"),
  "javaVersion": $([ -n "$JAVA_VERSION" ] && echo "\"$JAVA_VERSION\"" || echo "null"),
  "javaProjectVersion": $([ -n "$JAVA_PROJECT_VERSION" ] && echo "\"$JAVA_PROJECT_VERSION\"" || echo "null"),
  "branch": "$(printf '%s' "$BRANCH" | sed 's/"/\\"/g')",
  "dependencies": {
    "postgresql": $DEP_POSTGRESQL,
    "mysql": $DEP_MYSQL,
    "redis": $DEP_REDIS,
    "kafka": $DEP_KAFKA,
    "rabbitmq": $DEP_RABBITMQ,
    "docker": $DEP_DOCKER
  }
}
PROFILE_EOF
log "Project profile written → $PROFILE_FILE"

# --- Ensure workflow-state.json exists (CRITICAL for phase tracking) ---
# This is hook-enforced, not prompt-dependent. If the file doesn't exist,
# create it with IDLE phase. /plan will update it to PLAN when it runs.
# This guarantees all downstream hooks (workflow-tracker, quality-gate,
# pre-compact, build-checkpoint) always have a file to read.
WORKFLOW_FILE="${PROFILE_DIR}/workflow-state.json"
if [ ! -f "$WORKFLOW_FILE" ]; then
  cat > "$WORKFLOW_FILE" <<WF_EOF
{
  "phase": "IDLE",
  "task": null,
  "startedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phaseHistory": [],
  "decisions": [],
  "artifacts": {},
  "autoTransition": true,
  "retryCount": 0
}
WF_EOF
  log "Workflow state initialized (IDLE) → $WORKFLOW_FILE"
else
  log "Workflow state exists → phase=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$WORKFLOW_FILE" 2>/dev/null | head -1 | sed 's/.*: *"//' | sed 's/".*//')"
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

  # Inject compact summaries of Summer sub-skills (trigger keywords only — load full skill on demand)
  CONTEXT="${CONTEXT}### Summer Sub-Skills (load on demand via Skill tool)\n\n"
  CONTEXT="${CONTEXT}| Sub-Skill | Trigger Keywords | Load When |\n"
  CONTEXT="${CONTEXT}|-----------|-----------------|----------|\n"
  CONTEXT="${CONTEXT}| \`summer-rest\` | BaseController, RequestHandler, @Handler, WebClientBuilderFactory | Building REST endpoints or HTTP handlers |\n"
  CONTEXT="${CONTEXT}| \`summer-data\` | AuditService, OutboxService, f8a.audit, f8a.outbox | Audit logging, outbox/event persistence |\n"
  CONTEXT="${CONTEXT}| \`summer-security\` | @AuthRoles, ReactiveKeycloakClient, f8a.security | Auth roles, Keycloak integration, security config |\n"
  CONTEXT="${CONTEXT}| \`summer-ratelimit\` | RateLimiterService, f8a.rate-limiter (v0.2.2+) | Rate limiting, token bucket, throttling |\n"
  CONTEXT="${CONTEXT}| \`summer-test\` | src/test/ + summer-test dependency | Integration/blackbox tests using Summer test utilities |\n\n"
  CONTEXT="${CONTEXT}Load each sub-skill via: \`Skill tool \u2192 devco-agent-skills:summer-{name}\`\n\n"
  log "Summer sub-skill summaries injected \u2713"
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
# Memory Restoration (bidirectional memory — reads session-summary.json)
# ---------------------------------------------------------------------------
SESSION_SUMMARY_FILE="${PROJECT_ROOT}/.claude/sessions/session-summary.json"
if [ -f "$SESSION_SUMMARY_FILE" ] && command -v python3 &>/dev/null; then
  MEMORY_CTX=$(python3 -c "
import json, sys

try:
    s = json.load(open('$SESSION_SUMMARY_FILE'))
    task  = s.get('task') or 'unknown'
    phase = s.get('phase') or 'unknown'

    # Top-3 decisions (cap each at 120 chars)
    decisions = s.get('decisions', [])
    top3 = [str(d)[:120] for d in decisions[:3]]

    # Top-2 skills by usage count
    skills = s.get('skillsUsed', {})
    top_skills = sorted(skills.items(), key=lambda x: x[1], reverse=True)[:2]
    skill_names = [k for k, _ in top_skills]

    lines = []
    lines.append('## Previous Session Context')
    lines.append(f'- **Last Task**: {task[:200]}')
    lines.append(f'- **Last Phase**: {phase}')
    if top3:
        lines.append(f'- **Key Decisions**: {chr(10).join(\"  - \" + d for d in top3)}')
    if skill_names:
        lines.append(f'- **Skills Used**: {chr(44).join(skill_names)}')
    lines.append('Resume from where you left off. Check .claude/workflow-state.json for current state.')

    print('\n'.join(lines))
except Exception as e:
    sys.stderr.write(f'[SessionInit] WARNING: Could not restore session summary: {e}\n')
    sys.exit(1)
" 2>/dev/null) && {
    CONTEXT="${CONTEXT}${MEMORY_CTX}\n\n"
    log "Previous session context restored ✓"
  } || true
fi

# Check for pending auto-extract signal
AUTO_EXTRACT_PENDING="${PROJECT_ROOT}/.claude/instincts/personal/.auto-extract-pending.json"
if [ -f "$AUTO_EXTRACT_PENDING" ]; then
  CONTEXT="${CONTEXT}> **Note**: A high-activity session was detected. Run \`/meta learn extract\` to capture patterns from last session.\n\n"
  log "Auto-extract pending signal detected"
fi

# ---------------------------------------------------------------------------
# Config & Profile Injection (agents MUST receive config at runtime)
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

# ---------------------------------------------------------------------------
# Skills-loaded registry - pre-populated with auto-detected likely skills (R1)
#
# skill-router.sh blocks file edits when the matching skill is NOT in
# skills-loaded.json. In non-interactive mode (claude -p), the agent cannot
# get user approval to update this file, causing 100% write-task failure
# (see plugin-review-agent-skills/benchmark_results.md - 12/12 blocked).
#
# Fix: pre-populate at session start with skills the project profile suggests
# will be needed. The agent still loads the skill via the Skill tool at edit
# time; this just stops the soft-block from being a hard fail in -p mode.
#
# Disable via env: DEVCO_PREPOPULATE_SKILLS=0
# ---------------------------------------------------------------------------
mkdir -p "${PROJECT_ROOT}/.claude/sessions" 2>/dev/null || true
SKILLS_LOADED="${PROJECT_ROOT}/.claude/sessions/skills-loaded.json"

PREPOP=""
if [ "${DEVCO_PREPOPULATE_SKILLS:-1}" = "1" ]; then
  if [ "$BUILD_TOOL" != "unknown" ]; then
    PREPOP="$PREPOP coding-standards testing-workflow architecture api-design"
  fi
  case "$SPRING_TYPE" in
    *WebFlux*|*MVC*|*Servlet*) PREPOP="$PREPOP spring-patterns" ;;
  esac
  if [ "$DEP_POSTGRESQL" = "true" ] || [ "$DEP_MYSQL" = "true" ]; then
    PREPOP="$PREPOP database-patterns"
  fi
  if [ "$DEP_KAFKA" = "true" ] || [ "$DEP_RABBITMQ" = "true" ]; then
    PREPOP="$PREPOP messaging-patterns"
  fi
  [ "$DEP_REDIS" = "true" ] && PREPOP="$PREPOP redis-patterns"
  if [ "$SUMMER_DETECTED" = "true" ]; then
    PREPOP="$PREPOP summer-core summer-rest summer-data summer-security summer-test"
  fi
fi

# Render dedup'd JSON array of skill names
SKILLS_JSON=$(printf '%s' "$PREPOP" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | python3 -c "
import sys, json
skills = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(skills))
" 2>/dev/null)
[ -z "$SKILLS_JSON" ] && SKILLS_JSON="[]"

SKILLS_COUNT=$(printf '%s' "$PREPOP" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | wc -l | tr -d ' ')

cat > "$SKILLS_LOADED" <<SKILLS_EOF
{"skills":${SKILLS_JSON},"resetAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","prepopulated":true}
SKILLS_EOF
log "Skills-loaded pre-populated -> $SKILLS_LOADED (${SKILLS_COUNT} skills auto-acknowledged)"

# Output
printf '%b' "$CONTEXT" 2>/dev/null || true

log "Session initialized \u2713"
exit 0
