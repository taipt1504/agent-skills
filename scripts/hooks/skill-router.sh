#!/usr/bin/env bash
# =============================================================================
# skill-router.sh — PreToolUse Skill Hint Router (v4.0 — announcement-only)
# =============================================================================
# Hints at the skill that matches the file being edited. Does NOT block.
# Uses: filename patterns → directory patterns → file content → NL triggers.
# Fires on: PreToolUse (Edit|Write|MultiEdit)
#
# Behavior (v4.0):
#   - Skill matched → emit stderr announcement, exit 0 (pass through)
#   - No match → exit 0 (pass through)
#
# Rationale: skills-loaded.json gate caused multi-agent dispatch failures
# (see REFACTOR_PLAN.md §3.6.1 Stage 2). Replaced with announcement contract
# per superpowers pattern: agent announces loaded skills in chat, no file gate.
# Pre-flight discovery (preflight-gate.sh) handles enforcement now.
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "skill-router" || exit 0

# Read stdin (tool input JSON)
DATA=$(cat)

# Extract file path from JSON
FILE_PATH=$(echo "$DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

if [ -z "$FILE_PATH" ]; then
  echo "$DATA"
  exit 0
fi

# Only route for Java files
if [[ ! "$FILE_PATH" =~ \.java$ ]] && [[ ! "$FILE_PATH" =~ \.yml$ ]] && [[ ! "$FILE_PATH" =~ \.sql$ ]]; then
  echo "$DATA"
  exit 0
fi

FILENAME="$(basename "$FILE_PATH")"
SKILL=""

# Route based on file patterns
case "$FILENAME" in
  *Controller.java|*Handler.java|*Router.java)
    SKILL="spring-webflux-patterns" ;;
  *SecurityConfig*|*AuthConfig*)
    SKILL="spring-security" ;;
  *Repository.java|*Entity.java)
    SKILL="database-patterns" ;;
  *Test.java|*Spec.java)
    SKILL="testing-workflow" ;;
  *.sql)
    SKILL="database-patterns" ;;
esac

# Directory-based routing (fires after filename patterns, before content check)
# Catches new/empty files where content-based routing would fail.
if [ -z "$SKILL" ]; then
  LOWER_DIR="$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')"
  if echo "$LOWER_DIR" | grep -qE '/controller/|/handler/'; then
    SKILL="spring-webflux-patterns"
  elif echo "$LOWER_DIR" | grep -qE '/security/'; then
    SKILL="spring-security"
  elif echo "$LOWER_DIR" | grep -qE '/repository/|/entity/'; then
    SKILL="database-patterns"
  elif echo "$LOWER_DIR" | grep -qE '/consumer/|/producer/|/listener/'; then
    SKILL="messaging-patterns"
  elif echo "$LOWER_DIR" | grep -qE '/config/' && echo "$LOWER_DIR" | grep -qE 'security|auth|jwt|oauth'; then
    SKILL="spring-security"
  fi
  # Note: /test/ directory matches are advisory-only (do not block test files)
fi

# Check file content for more specific routing
if [ -z "$SKILL" ] && [ -f "$FILE_PATH" ]; then
  if grep -q '@KafkaListener\|KafkaTemplate\|@RabbitListener\|RabbitTemplate' "$FILE_PATH" 2>/dev/null; then
    SKILL="messaging-patterns"
  elif grep -q 'ReactiveRedisTemplate\|RedisTemplate\|@Cacheable' "$FILE_PATH" 2>/dev/null; then
    SKILL="redis-patterns"
  elif grep -q '@PreAuthorize\|SecurityWebFilterChain\|SecurityFilterChain' "$FILE_PATH" 2>/dev/null; then
    SKILL="spring-security"
  elif grep -q 'Mono\.\|Flux\.\|StepVerifier' "$FILE_PATH" 2>/dev/null; then
    SKILL="spring-webflux-patterns"
  fi
fi

# Summer sub-skill routing (only if summer detected)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
PROFILE_FILE="${PROJECT_ROOT}/.claude/project-profile.json"
SUMMER_DETECTED=false

if [ -f "$PROFILE_FILE" ]; then
  SUMMER_VAL=$(grep -o '"summer"[[:space:]]*:[[:space:]]*[a-z]*' "$PROFILE_FILE" | head -1 | sed 's/.*: *//')
  [ "$SUMMER_VAL" = "true" ] && SUMMER_DETECTED=true
else
  # Fallback: scan build file
  BUILD_FILE=""
  [ -f "$PROJECT_ROOT/build.gradle" ] && BUILD_FILE="$PROJECT_ROOT/build.gradle"
  [ -f "$PROJECT_ROOT/build.gradle.kts" ] && BUILD_FILE="$PROJECT_ROOT/build.gradle.kts"
  if [ -n "$BUILD_FILE" ] && grep -q "io.f8a.summer" "$BUILD_FILE" 2>/dev/null; then
    SUMMER_DETECTED=true
  fi
fi

if [ "$SUMMER_DETECTED" = true ] && [ -f "$FILE_PATH" ]; then
  if grep -q 'BaseController\|RequestHandler\|@Handler\|WebClientBuilderFactory' "$FILE_PATH" 2>/dev/null; then
    SKILL="summer-rest"
  elif grep -q 'AuditService\|OutboxService\|f8a\.audit\|f8a\.outbox' "$FILE_PATH" 2>/dev/null; then
    SKILL="summer-data"
  elif grep -q '@AuthRoles\|ReactiveKeycloakClient\|f8a\.security' "$FILE_PATH" 2>/dev/null; then
    SKILL="summer-security"
  elif grep -q 'RateLimiterService\|f8a\.rate-limiter' "$FILE_PATH" 2>/dev/null; then
    SKILL="summer-ratelimit"
  fi
fi

# --- Natural language trigger matching (fallback when no file/content match) ---
if [ -z "$SKILL" ]; then
  # Lowercase file path for case-insensitive matching
  LOWER_PATH="$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')"

  # Hardcoded natural language trigger lookup (avoids reading 18 SKILL.md files)
  # Format: "trigger phrase|skill-name"
  NL_TRIGGERS=(
    "rest endpoint|spring-webflux-patterns"
    "api handler|spring-webflux-patterns"
    "pagination|spring-webflux-patterns"
    "web filter|spring-webflux-patterns"
    "webclient|spring-webflux-patterns"
    "jwt auth|spring-security"
    "cors config|spring-security"
    "security filter|spring-security"
    "oauth|spring-security"
    "authentication|spring-security"
    "db migration|database-patterns"
    "jpa entity|database-patterns"
    "connection pool|database-patterns"
    "query optimization|database-patterns"
    "r2dbc|database-patterns"
    "kafka consumer|messaging-patterns"
    "message queue|messaging-patterns"
    "event streaming|messaging-patterns"
    "rabbitmq|messaging-patterns"
    "dead letter|messaging-patterns"
    "redis cache|redis-patterns"
    "distributed lock|redis-patterns"
    "rate limit with redis|redis-patterns"
    "cache eviction|redis-patterns"
    "structured logging|observability-patterns"
    "metrics|observability-patterns"
    "distributed tracing|observability-patterns"
    "health check|observability-patterns"
    "alerting|observability-patterns"
    "api design|api-design"
    "error format|api-design"
    "pagination design|api-design"
    "openapi|api-design"
    "rest conventions|api-design"
    "hexagonal|architecture"
    "cqrs|architecture"
    "domain event|architecture"
    "package structure|architecture"
    "ports and adapters|architecture"
    "naming convention|coding-standards"
    "java pattern|coding-standards"
    "code style|coding-standards"
    "immutability|coding-standards"
    "write test|testing-workflow"
    "tdd|testing-workflow"
    "coverage|testing-workflow"
    "testcontainers|testing-workflow"
    "step verifier|testing-workflow"
    "rate limiter|summer-ratelimit"
    "summer rate limit|summer-ratelimit"
    "token bucket|summer-ratelimit"
    "summer handler|summer-rest"
    "request handler|summer-rest"
    "summer controller|summer-rest"
    "audit service|summer-data"
    "outbox pattern|summer-data"
    "summer audit|summer-data"
    "auth roles|summer-security"
    "keycloak client|summer-security"
    "summer security|summer-security"
    "summer test|summer-test"
    "blackbox test|summer-test"
    "summer testcontainer|summer-test"
    "summer framework|summer-core"
    "summer platform|summer-core"
  )

  for entry in "${NL_TRIGGERS[@]}"; do
    TRIGGER="${entry%%|*}"
    MATCHED_SKILL="${entry##*|}"
    if echo "$LOWER_PATH" | grep -qi "$TRIGGER" 2>/dev/null; then
      SKILL="$MATCHED_SKILL"
      break
    fi
  done
fi

if [ -n "$SKILL" ]; then
  SKILL_PATH="skills/$SKILL/SKILL.md"
  # Announcement only — non-blocking. Agent announces skill loaded in chat per
  # the rules/common/skill-enforcement.md 1% rule. Pre-flight is the gate now.
  printf '[skill-router] Suggested skill for %s: %s (path: %s)\n' \
    "$FILENAME" "$SKILL" "$SKILL_PATH" >&2
fi

# Always pass through — no blocking
printf '%s' "$DATA"
exit 0
