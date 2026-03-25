#!/usr/bin/env bash
# =============================================================================
# subagent-init.sh — SubagentStart Context Injection (v3.1)
# =============================================================================
# Injects skill protocol + project context into every subagent via additionalContext.
# Fires on: SubagentStart (synchronous)
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "subagent-init" || exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

# --- Detect project type ---
SPRING_TYPE=""
BUILD_FILE=""
[ -f "build.gradle" ] && BUILD_FILE="build.gradle"
[ -f "build.gradle.kts" ] && BUILD_FILE="build.gradle.kts"
[ -f "pom.xml" ] && BUILD_FILE="pom.xml"

if [ -n "$BUILD_FILE" ]; then
  grep -q "spring-boot-starter-webflux" "$BUILD_FILE" 2>/dev/null && SPRING_TYPE="WebFlux"
  [ -z "$SPRING_TYPE" ] && grep -q "spring-boot-starter-web" "$BUILD_FILE" 2>/dev/null && SPRING_TYPE="MVC"
fi

# --- Detect Summer ---
SUMMER_DETECTED=false
if [ -n "$BUILD_FILE" ] && grep -q "io.f8a.summer" "$BUILD_FILE" 2>/dev/null; then
  SUMMER_DETECTED=true
fi

# --- Build context ---
CTX="## Subagent Skill Protocol (MANDATORY)\n\n"
CTX="${CTX}Before ANY file operation:\n"
CTX="${CTX}1. Load the matching skill via Skill tool (e.g. devco-agent-skills:spring-patterns for Controller files)\n"
CTX="${CTX}2. Announce: \"Using skill: {name} for {reason}\"\n"
CTX="${CTX}3. If no match: state \"No matching skill found\"\n\n"
CTX="${CTX}### Quick Skill Registry\n"
CTX="${CTX}| Pattern | Skill |\n|---|---|\n"
CTX="${CTX}| *Controller, *Handler | devco-agent-skills:spring-patterns |\n"
CTX="${CTX}| *SecurityConfig, JWT | devco-agent-skills:spring-security |\n"
CTX="${CTX}| *Repository, *.sql | devco-agent-skills:database-patterns |\n"
CTX="${CTX}| *Test.java | devco-agent-skills:testing-workflow |\n"
CTX="${CTX}| Kafka*, Rabbit* | devco-agent-skills:messaging-patterns |\n"
CTX="${CTX}| Redis*, cache | devco-agent-skills:redis-patterns |\n"
CTX="${CTX}| Any Java file | devco-agent-skills:coding-standards |\n\n"
CTX="${CTX}### Hard Blocks\n"
CTX="${CTX}- .block() in src/main/ → CRITICAL — fix immediately\n"
CTX="${CTX}- No git commit/push — only the user commits\n"
CTX="${CTX}- No code without approved plan+spec (exception: ≤5 line trivial fixes)\n"
CTX="${CTX}- **Stopping after BUILD without VERIFY+REVIEW is FORBIDDEN**\n\n"
CTX="${CTX}### Workflow Completion (CRITICAL)\n"
CTX="${CTX}After BUILD: IMMEDIATELY run /verify full, then /review. A task is NOT done until REVIEW completes.\n"
CTX="${CTX}\n### Knowledge Graph Memory\n"
CTX="${CTX}Use mcp__memory__search_nodes before starting work to find relevant past context.\n"
CTX="${CTX}After completing work, use mcp__memory__create_entities for new findings.\n"

# --- Summer injection ---
if [ "$SUMMER_DETECTED" = true ]; then
  CTX="${CTX}\n### Summer Framework ACTIVE\n"
  CTX="${CTX}This project uses Summer Framework. Load devco-agent-skills:summer-core FIRST.\n"
  CTX="${CTX}Summer patterns supersede standard Spring patterns.\n"

  # Inject summer-core content if available
  SUMMER_SKILL="${CLAUDE_PLUGIN_ROOT:-}/skills/summer-core/SKILL.md"
  [ ! -f "$SUMMER_SKILL" ] && SUMMER_SKILL="$(dirname "$0")/../../skills/summer-core/SKILL.md"
  if [ -f "$SUMMER_SKILL" ]; then
    SUMMER_CONTENT="$(cat "$SUMMER_SKILL" 2>/dev/null | sed 's/"/\\"/g; s/$/\\n/' | tr -d '\n')"
    CTX="${CTX}\n${SUMMER_CONTENT}"
  fi
fi

[ -n "$SPRING_TYPE" ] && CTX="${CTX}\n\n**Stack**: Spring ${SPRING_TYPE}"

# --- Output structured JSON ---
# Escape for JSON
CTX_ESCAPED="$(printf '%s' "$CTX" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')"

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}' "$CTX_ESCAPED"
exit 0
