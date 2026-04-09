#!/usr/bin/env bash
# =============================================================================
# skill-router.sh — PreToolUse Skill Router (v3.2)
# =============================================================================
# Checks file→skill mapping before file operations, enforces skill loading.
# Uses: filename patterns → directory patterns → file content → NL triggers.
# Fires on: PreToolUse (Edit|Write|MultiEdit)
#
# Behavior:
#   - If skill matched AND skill NOT in skills-loaded.json → exit 2 (block)
#   - If skill matched AND skill already loaded → exit 0 (pass through)
#   - If no skill matched → exit 0 (pass through)
#
# Registry: .claude/sessions/skills-loaded.json
#   Updated by: session-init.sh (reset on session start)
#   The agent's Skill tool usage is tracked externally; agents should update
#   skills-loaded.json after loading a skill, or the next hook call will
#   block again. This creates a soft-block loop that enforces skill loading.
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

# Directory-based routing (fires after filename patterns, before content check)
# Catches new/empty files where content-based routing would fail.
if [ -z "$SKILL" ]; then
  LOWER_DIR="$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')"
  if echo "$LOWER_DIR" | grep -qE '/controller/|/handler/'; then
    SKILL="spring-patterns"
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

  # --- Check loaded-skills registry ---
  # skills-loaded.json is reset by session-init.sh on session start.
  # Agents should update this file after loading a skill to avoid repeated blocks.
  SKILLS_LOADED_FILE="${PROJECT_ROOT}/.claude/sessions/skills-loaded.json"
  ALREADY_LOADED=false
  if [ -f "$SKILLS_LOADED_FILE" ]; then
    if grep -q "\"$SKILL\"" "$SKILLS_LOADED_FILE" 2>/dev/null; then
      ALREADY_LOADED=true
    fi
  fi

  if [ "$ALREADY_LOADED" = true ]; then
    # Skill already loaded — pass through, no interruption
    printf '%s' "$DATA"
    exit 0
  fi

  # Skill NOT loaded — soft-block: require the agent to load the skill first
  BLOCK_MSG="BLOCKED: Load skill '${SKILL}' before editing ${FILENAME}. Use Skill tool: devco-agent-skills:${SKILL} (path: ${SKILL_PATH}). After loading, update .claude/sessions/skills-loaded.json to acknowledge."
  printf '{"decision":"block","reason":"%s"}' \
    "$(printf '%s' "$BLOCK_MSG" | sed 's/"/\\"/g')"
  exit 2
fi

# No skill match — pass through original data
printf '%s' "$DATA"
exit 0
