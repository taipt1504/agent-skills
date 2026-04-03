#!/usr/bin/env bash
# =============================================================================
# subagent-init.sh — SubagentStart Context Injection (v3.1.1)
# =============================================================================
# Injects skill protocol + project context into every subagent via additionalContext.
# Fires on: SubagentStart (synchronous)
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "subagent-init" || exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

# --- Read project profile (or fallback to detection) ---
PROFILE_FILE="${PROJECT_ROOT}/.claude/project-profile.json"
SPRING_TYPE=""
SUMMER_DETECTED=false

if [ -f "$PROFILE_FILE" ]; then
  SPRING_TYPE=$(grep -o '"springType"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROFILE_FILE" | head -1 | sed 's/.*: *"//' | sed 's/".*//')
  SUMMER_VAL=$(grep -o '"summer"[[:space:]]*:[[:space:]]*[a-z]*' "$PROFILE_FILE" | head -1 | sed 's/.*: *//')
  [ "$SUMMER_VAL" = "true" ] && SUMMER_DETECTED=true
else
  # Fallback: detect from build files
  BUILD_FILE=""
  [ -f "build.gradle" ] && BUILD_FILE="build.gradle"
  [ -f "build.gradle.kts" ] && BUILD_FILE="build.gradle.kts"
  [ -f "pom.xml" ] && BUILD_FILE="pom.xml"

  if [ -n "$BUILD_FILE" ]; then
    grep -q "spring-boot-starter-webflux" "$BUILD_FILE" 2>/dev/null && SPRING_TYPE="WebFlux"
    [ -z "$SPRING_TYPE" ] && grep -q "spring-boot-starter-web" "$BUILD_FILE" 2>/dev/null && SPRING_TYPE="MVC"
  fi

  if [ -n "$BUILD_FILE" ] && grep -q "io.f8a.summer" "$BUILD_FILE" 2>/dev/null; then
    SUMMER_DETECTED=true
  fi
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
CTX="${CTX}After BUILD: IMMEDIATELY run /verify full, then /dc-review. A task is NOT done until REVIEW completes.\n"
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

# --- Agent skill manifest resolution ---
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -z "$PLUGIN_ROOT" ] && PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"

if [ -n "$PLUGIN_ROOT" ] && [ -d "$PLUGIN_ROOT/agents" ]; then
  for AGENT_FILE in "$PLUGIN_ROOT/agents"/*.md; do
    [ -f "$AGENT_FILE" ] || continue
    AGENT_NAME="$(basename "$AGENT_FILE" .md)"

    # Extract always-required skills from frontmatter
    ALWAYS_SKILLS=$(sed -n '/^requiredSkills:/,/^requiredCommands:/p' "$AGENT_FILE" 2>/dev/null \
      | sed -n '/always:/,/conditional:/p' \
      | grep -oE '"[^"]*"' | tr -d '"' | tr '\n' ' ')

    if [ -n "$ALWAYS_SKILLS" ]; then
      # Inject skill summaries for this agent's required skills
      for SKILL_NAME in $ALWAYS_SKILLS; do
        SKILL_FILE="${PLUGIN_ROOT}/skills/${SKILL_NAME}/SKILL.md"
        if [ -f "$SKILL_FILE" ]; then
          # Extract first 30 lines as summary (skip frontmatter)
          SKILL_SUMMARY=$(sed -n '/^---$/,/^---$/d; 1,30p' "$SKILL_FILE" 2>/dev/null | head -30 | tr '\n' ' ' | sed 's/"/\\"/g')
          CTX="${CTX}\n### Loaded Skill: ${SKILL_NAME}\n${SKILL_SUMMARY}\n"
        fi
      done

      # Resolve conditional skills based on project profile
      if [ -f "$PROFILE_FILE" ]; then
        # Check each conditional category
        if echo "$ALWAYS_SKILLS" | grep -q "spring-patterns" 2>/dev/null || [ -n "$SPRING_TYPE" ]; then
          COND_SKILLS=$(sed -n '/^requiredSkills:/,/^requiredCommands:/p' "$AGENT_FILE" 2>/dev/null \
            | sed -n '/conditional:/,/^[a-z]/p' \
            | grep -oE '"[^"]*"' | tr -d '"' | tr '\n' ' ')
          for COND_SKILL in $COND_SKILLS; do
            COND_FILE="${PLUGIN_ROOT}/skills/${COND_SKILL}/SKILL.md"
            if [ -f "$COND_FILE" ] && ! echo "$ALWAYS_SKILLS" | grep -q "$COND_SKILL"; then
              CTX="${CTX}\n### Conditional Skill Available: ${COND_SKILL}\n"
            fi
          done
        fi
      fi
      # v3.1.1: Removed break — inject ALL agent skills since SubagentStart
      # doesn't pass agent name. Let conditional resolution use project-profile.
    fi
  done
fi

# ---------------------------------------------------------------------------
# Config injection for subagent (v3.1.1)
# ---------------------------------------------------------------------------
CONFIG_FILE="${PROJECT_ROOT}/.claude/devco-config.json"

if [ -f "$CONFIG_FILE" ] && command -v python3 &>/dev/null; then
  CONFIG_SECTION=$(python3 -c "
import json
c = json.load(open('$CONFIG_FILE'))
wf = c.get('workflow', {})
team = c.get('team', {})
mode = c.get('mode', 'standard')
lines = []
lines.append('\n## Runtime Config')
lines.append(f'Mode: {mode} | autoVerify: {wf.get(\"autoVerify\", True)} | autoReview: {wf.get(\"autoReview\", True)}')
lines.append(f'maxRetryOnFail: {wf.get(\"maxRetryOnFail\", 3)} | noProgressThreshold: {wf.get(\"noProgressThreshold\", 3)}')
if team.get('enabled'):
    lines.append(f'Team: ENABLED (maxTeammates: {team.get(\"maxTeammates\", 4)})')
if mode == 'yolo':
    lines.append('Mode yolo: Skip plan/spec confirmations. Warn on violations, do not block.')
elif mode == 'strict':
    lines.append('Mode strict: All gates enforced. Block on violations.')
print('\n'.join(lines))
" 2>/dev/null) || true

  [ -n "$CONFIG_SECTION" ] && CTX="${CTX}${CONFIG_SECTION}\n"
fi

# --- Output structured JSON ---
# Escape for JSON
CTX_ESCAPED="$(printf '%s' "$CTX" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')"

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}' "$CTX_ESCAPED"
exit 0
