#!/usr/bin/env bash
# =============================================================================
# skill-router.sh — PreToolUse Skill Router (v3.0)
# =============================================================================
# Checks file→skill mapping before file operations, suggests relevant skill.
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
BUILD_FILE=""
[ -f "$PROJECT_ROOT/build.gradle" ] && BUILD_FILE="$PROJECT_ROOT/build.gradle"
[ -f "$PROJECT_ROOT/build.gradle.kts" ] && BUILD_FILE="$PROJECT_ROOT/build.gradle.kts"

if [ -n "$BUILD_FILE" ] && grep -q "io.f8a.summer" "$BUILD_FILE" 2>/dev/null; then
  if [ -f "$FILE_PATH" ]; then
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
