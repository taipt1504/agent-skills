#!/usr/bin/env bash
# =============================================================================
# skill-router.sh — PreToolUse Skill Router (v3.1)
# =============================================================================
# Checks file→skill mapping before file operations, suggests relevant skill.
# Uses: filename patterns → file content → natural language triggers (hardcoded).
# Fires on: PreToolUse (Edit|Write|MultiEdit)
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
    SKILL="spring-patterns" ;;
  *SecurityConfig*|*AuthConfig*)
    SKILL="spring-security" ;;
  *Repository.java|*Entity.java)
    SKILL="database-patterns" ;;
  *Test.java|*Spec.java)
    SKILL="testing-workflow" ;;
  *.sql)
    SKILL="database-patterns" ;;
esac

# Check file content for more specific routing
if [ -z "$SKILL" ] && [ -f "$FILE_PATH" ]; then
  if grep -q '@KafkaListener\|KafkaTemplate\|@RabbitListener\|RabbitTemplate' "$FILE_PATH" 2>/dev/null; then
    SKILL="messaging-patterns"
  elif grep -q 'ReactiveRedisTemplate\|RedisTemplate\|@Cacheable' "$FILE_PATH" 2>/dev/null; then
    SKILL="redis-patterns"
  elif grep -q '@PreAuthorize\|SecurityWebFilterChain\|SecurityFilterChain' "$FILE_PATH" 2>/dev/null; then
    SKILL="spring-security"
  elif grep -q 'Mono\.\|Flux\.\|StepVerifier' "$FILE_PATH" 2>/dev/null; then
    SKILL="spring-patterns"
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
    "rest endpoint|spring-patterns"
    "api handler|spring-patterns"
    "pagination|spring-patterns"
    "web filter|spring-patterns"
    "webclient|spring-patterns"
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
  MSG="LOAD SKILL before editing $FILENAME: Use Skill tool to load devco-agent-skills:$SKILL (or read $SKILL_PATH)"
  # Output structured JSON with additionalContext — agent will see this
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}' \
    "$(printf '%s' "$MSG" | sed 's/"/\\"/g')"
  exit 0
fi

# No skill match — pass through original data
printf '%s' "$DATA"
exit 0
