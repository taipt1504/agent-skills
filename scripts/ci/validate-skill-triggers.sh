#!/usr/bin/env bash
# =============================================================================
# validate-skill-triggers.sh — Skill Trigger Validation (v3.1)
# =============================================================================
# Validates that natural language queries match the correct skill via triggers.
# Expects ≥18/20 correct matches. Compatible with bash 3.x (macOS).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/../../skills" && pwd)"

PASS=0
FAIL=0
TOTAL=20

# --- Natural language trigger table (pipe-separated: "trigger|skill") ---
# Mirrors the NL_TRIGGERS array in skill-router.sh
TRIGGERS="
rest endpoint|spring-patterns
api handler|spring-patterns
pagination|spring-patterns
web filter|spring-patterns
webclient|spring-patterns
jwt auth|spring-security
cors config|spring-security
security filter|spring-security
oauth|spring-security
authentication|spring-security
db migration|database-patterns
jpa entity|database-patterns
connection pool|database-patterns
query optimization|database-patterns
r2dbc|database-patterns
kafka consumer|messaging-patterns
message queue|messaging-patterns
event streaming|messaging-patterns
rabbitmq|messaging-patterns
dead letter|messaging-patterns
redis cache|redis-patterns
distributed lock|redis-patterns
rate limit with redis|redis-patterns
cache eviction|redis-patterns
structured logging|observability-patterns
metrics|observability-patterns
distributed tracing|observability-patterns
health check|observability-patterns
alerting|observability-patterns
api design|api-design
error format|api-design
pagination design|api-design
openapi|api-design
rest conventions|api-design
hexagonal|architecture
cqrs|architecture
domain event|architecture
package structure|architecture
ports and adapters|architecture
naming convention|coding-standards
java pattern|coding-standards
code style|coding-standards
immutability|coding-standards
records|coding-standards
write test|testing-workflow
tdd|testing-workflow
coverage|testing-workflow
testcontainers|testing-workflow
step verifier|testing-workflow
rate limiter|summer-ratelimit
summer rate limit|summer-ratelimit
token bucket|summer-ratelimit
summer handler|summer-rest
request handler|summer-rest
summer controller|summer-rest
audit service|summer-data
outbox pattern|summer-data
summer audit|summer-data
auth roles|summer-security
keycloak client|summer-security
summer security|summer-security
summer test|summer-test
blackbox test|summer-test
summer testcontainer|summer-test
summer framework|summer-core
summer platform|summer-core
"

# --- Match function: find longest trigger phrase in query ---
match_skill() {
  local query="$1"
  local lower_query
  lower_query="$(echo "$query" | tr '[:upper:]' '[:lower:]')"

  local best_match=""
  local best_len=0

  echo "$TRIGGERS" | while IFS='|' read -r trigger skill; do
    [ -z "$trigger" ] && continue
    if echo "$lower_query" | grep -qi "$trigger" 2>/dev/null; then
      local len=${#trigger}
      if [ "$len" -gt "$best_len" ]; then
        best_len=$len
        best_match="$skill"
      fi
    fi
  done
  # Subshell issue: use a temp approach instead
  echo "$best_match"
}

# The while loop runs in a subshell, so variables don't propagate.
# Rewrite match_skill to avoid this:
match_skill() {
  local query="$1"
  local lower_query
  lower_query="$(echo "$query" | tr '[:upper:]' '[:lower:]')"

  local best_match=""
  local best_len=0
  local trigger skill len

  while IFS='|' read -r trigger skill; do
    [ -z "$trigger" ] && continue
    if echo "$lower_query" | grep -qi "$trigger" 2>/dev/null; then
      len=${#trigger}
      if [ "$len" -gt "$best_len" ]; then
        best_len=$len
        best_match="$skill"
      fi
    fi
  done <<< "$TRIGGERS"

  echo "$best_match"
}

# --- Assertion ---
assert_skill() {
  local query="$1"
  local expected="$2"
  local actual
  actual="$(match_skill "$query")"

  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: \"$query\" -> $actual"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: \"$query\" -> got \"$actual\", expected \"$expected\""
  fi
}

# --- Validate frontmatter exists in all 18 SKILL.md files ---
echo "=== Frontmatter Validation ==="
MISSING_TRIGGERS=0
for skill_dir in "$SKILLS_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"
  skill_file="$skill_dir/SKILL.md"
  if [ -f "$skill_file" ]; then
    if ! grep -q "^triggers:" "$skill_file" 2>/dev/null; then
      echo "  MISSING triggers: $skill_name/SKILL.md"
      MISSING_TRIGGERS=$((MISSING_TRIGGERS + 1))
    fi
  fi
done
if [ "$MISSING_TRIGGERS" -eq 0 ]; then
  echo "  All SKILL.md files have triggers frontmatter"
else
  echo "  WARNING: $MISSING_TRIGGERS SKILL.md files missing triggers"
fi
echo

# --- 20 Test Cases ---
echo "=== Natural Language Trigger Tests ==="

assert_skill "add kafka consumer" "messaging-patterns"
assert_skill "configure jwt authentication" "spring-security"
assert_skill "create rest endpoint" "spring-patterns"
assert_skill "write database migration" "database-patterns"
assert_skill "add redis cache" "redis-patterns"
assert_skill "setup structured logging" "observability-patterns"
assert_skill "design api error format" "api-design"
assert_skill "implement hexagonal architecture" "architecture"
assert_skill "java naming convention" "coding-standards"
assert_skill "write unit test with tdd" "testing-workflow"
assert_skill "add rabbitmq listener" "messaging-patterns"
assert_skill "configure cors headers" "spring-security"
assert_skill "add distributed tracing" "observability-patterns"
assert_skill "create jpa entity" "database-patterns"
assert_skill "add web filter" "spring-patterns"
assert_skill "implement rate limiter" "summer-ratelimit"
assert_skill "design openapi spec" "api-design"
assert_skill "setup domain events with cqrs" "architecture"
assert_skill "configure testcontainers" "testing-workflow"
assert_skill "add health check endpoint" "observability-patterns"

echo
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [ "$PASS" -ge 18 ]; then
  echo "PASS (need >=18/20)"
  exit 0
else
  echo "FAIL (need >=18/20)"
  exit 1
fi
