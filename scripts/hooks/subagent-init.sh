#!/usr/bin/env bash
# =============================================================================
# subagent-init.sh — SubagentStart Context Injection
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
CTX="## Subagent Protocol (1% rule MANDATORY)\n\n"
CTX="${CTX}Per skills/preflight/SKILL.md + rules/common/skill-enforcement.md:\n"
CTX="${CTX}1. Read pre-flight artifact (path injected below) — enumerate skills + rules with relevance scores\n"
CTX="${CTX}2. Apply APPLY items, justify SKIP with concrete evidence\n"
CTX="${CTX}3. Announce: 'Skills loaded: {names}' before file operations\n"
CTX="${CTX}4. Cite skill names in result summary\n\n"

# --- Pre-flight 4 artifact injection (slice-executor receives) ---
PREFLIGHT_DIR="$PROJECT_ROOT/.claude/memory/preflight"
LATEST_EXECUTE_PREFLIGHT=""
if [ -d "$PREFLIGHT_DIR" ]; then
  LATEST_EXECUTE_PREFLIGHT=$(/bin/ls -t "$PREFLIGHT_DIR"/execute-*.md 2>/dev/null | head -1)
fi
if [ -n "$LATEST_EXECUTE_PREFLIGHT" ] && [ -f "$LATEST_EXECUTE_PREFLIGHT" ]; then
  CTX="${CTX}### Pre-flight 4 (Execute) artifact\n"
  CTX="${CTX}Path: ${LATEST_EXECUTE_PREFLIGHT#$PROJECT_ROOT/}\n"
  PREFLIGHT_CONTENT=$(/usr/bin/head -c 4000 "$LATEST_EXECUTE_PREFLIGHT" 2>/dev/null | sed 's/"/\\"/g' | tr '\n' ' ')
  CTX="${CTX}\`\`\`\n${PREFLIGHT_CONTENT}\n\`\`\`\n\n"
fi

# --- Plan + Spec artifact paths (shape-aware) ---
# Split shape: orchestrator passes plan_index + spec_index + plan_slice + spec_slice
# Single-file shape: orchestrator passes plan + spec (paths to .md files)
WORKFLOW_STATE="$PROJECT_ROOT/.claude/workflow-state.json"
if [ -f "$WORKFLOW_STATE" ] && command -v python3 &>/dev/null; then
  ARTIFACTS=$(python3 -c "
import json
try:
    s = json.load(open('$WORKFLOW_STATE'))
    a = s.get('artifacts', {})
    print(f\"PLAN={a.get('plan','')}|SPEC={a.get('spec','')}|PLAN_INDEX={a.get('plan_index','')}|SPEC_INDEX={a.get('spec_index','')}|PLAN_SLICE={a.get('plan_slice','')}|SPEC_SLICE={a.get('spec_slice','')}\")
except: pass
" 2>/dev/null)
  PLAN_PATH=$(echo "$ARTIFACTS" | sed -n 's/.*PLAN=\([^|]*\).*/\1/p')
  SPEC_PATH=$(echo "$ARTIFACTS" | sed -n 's/.*|SPEC=\([^|]*\).*/\1/p')
  PLAN_INDEX=$(echo "$ARTIFACTS" | sed -n 's/.*PLAN_INDEX=\([^|]*\).*/\1/p')
  SPEC_INDEX=$(echo "$ARTIFACTS" | sed -n 's/.*SPEC_INDEX=\([^|]*\).*/\1/p')
  PLAN_SLICE=$(echo "$ARTIFACTS" | sed -n 's/.*PLAN_SLICE=\([^|]*\).*/\1/p')
  SPEC_SLICE=$(echo "$ARTIFACTS" | sed -n 's/.*SPEC_SLICE=\([^|]*\).*/\1/p')

  # Detect shape
  if [ -n "$SPEC_SLICE" ] && [ -n "$PLAN_SLICE" ]; then
    # Split shape
    CTX="${CTX}### Plan + Spec (SPLIT shape — per-slice dispatch)\n"
    CTX="${CTX}- Plan index: ${PLAN_INDEX}\n"
    CTX="${CTX}- Spec index: ${SPEC_INDEX}\n"
    CTX="${CTX}- **YOUR plan slice:** ${PLAN_SLICE}\n"
    CTX="${CTX}- **YOUR spec slice:** ${SPEC_SLICE}\n"
    CTX="${CTX}Read ONLY your assigned slice files + index §1 Cross-cutting from spec_index.\n"
    CTX="${CTX}Do NOT read other slice files (context pollution).\n\n"

    # Inject cross-cutting (§1) from spec_index for slice-executor reference
    if [ -f "$PROJECT_ROOT/$SPEC_INDEX" ]; then
      XCUTTING=$(/usr/bin/awk '/^## 1\. Cross-cutting/,/^## 2\./' "$PROJECT_ROOT/$SPEC_INDEX" 2>/dev/null | /usr/bin/head -c 3000 | sed 's/"/\\"/g' | tr '\n' ' ')
      if [ -n "$XCUTTING" ]; then
        CTX="${CTX}### Cross-cutting (inherited from spec_index §1 — AUTHORITATIVE, no override w/o ADR)\n"
        CTX="${CTX}\`\`\`\n${XCUTTING}\n\`\`\`\n\n"
      fi
    fi
  elif [ -n "$PLAN_PATH" ] || [ -n "$SPEC_PATH" ]; then
    # Single-file shape
    CTX="${CTX}### Plan + Spec (SINGLE-FILE shape)\n"
    [ -n "$PLAN_PATH" ] && CTX="${CTX}- Plan: ${PLAN_PATH}\n"
    [ -n "$SPEC_PATH" ] && CTX="${CTX}- Spec: ${SPEC_PATH}\n"
    CTX="${CTX}Read your slice's scenarios from spec §5. Do NOT execute other slices.\n\n"
  fi
fi

# --- CONTEXT.md vocabulary injection ---
if [ -f "$PROJECT_ROOT/CONTEXT.md" ]; then
  VOCAB=$(awk '/^## Domain vocabulary/,/^## /' "$PROJECT_ROOT/CONTEXT.md" 2>/dev/null | /usr/bin/head -c 1500 | sed 's/"/\\"/g' | tr '\n' ' ')
  if [ -n "$VOCAB" ]; then
    CTX="${CTX}### CONTEXT.md vocabulary\n${VOCAB}\n\n"
  fi
fi

CTX="${CTX}### Hard Blocks\n"
CTX="${CTX}- .block() in reactive src/main/ → CRITICAL — fix immediately\n"
CTX="${CTX}- NO git commit/push — orchestrator/user only\n"
CTX="${CTX}- NO code without approved plan+spec (exception: trivial lane ≤5 lines)\n"
CTX="${CTX}- Stop after BUILD without VERIFY+REVIEW → FORBIDDEN\n"
CTX="${CTX}- Read other slices' specs → FORBIDDEN (context pollution)\n\n"
CTX="${CTX}### Workflow Completion\n"
CTX="${CTX}After all slices done: orchestrator runs /verify full → /dc-review. Task NOT done until REVIEW returns verdict.\n"

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
      # Inject skill summaries for this agent's required skills.
      # Extract first 15 lines after frontmatter — key patterns without bloating context.
      for SKILL_NAME in $ALWAYS_SKILLS; do
        SKILL_FILE="${PLUGIN_ROOT}/skills/${SKILL_NAME}/SKILL.md"
        if [ -f "$SKILL_FILE" ]; then
          # Skip YAML frontmatter (between --- delimiters), then take first 15 content lines.
          # Uses awk so frontmatter of any length is handled correctly.
          SKILL_SUMMARY=$(awk '
            /^---$/ { if (in_fm==0) { in_fm=1; next } else { in_fm=0; fm_done=1; next } }
            fm_done && count<15 { print; count++ }
          ' in_fm=0 fm_done=0 count=0 "$SKILL_FILE" 2>/dev/null \
            | sed 's/"/\\"/g' \
            | tr '\n' ' ')
          CTX="${CTX}\n### Loaded Skill: ${SKILL_NAME}\n${SKILL_SUMMARY}\n"
        fi
      done

      # Resolve conditional skills based on project profile
      if [ -f "$PROFILE_FILE" ]; then
        # Check each conditional category
        if echo "$ALWAYS_SKILLS" | grep -q "spring-webflux-patterns" 2>/dev/null || [ -n "$SPRING_TYPE" ]; then
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
# Session summary injection (bidirectional memory for subagents)
# ---------------------------------------------------------------------------
# v4.0: session-summary.json reads removed — populating writer was broken (all fields empty).
# Pre-flight artifact above is the canonical "what skills/rules apply" source.
# Current-triage.json injects lane:
TRIAGE_FILE="$PROJECT_ROOT/.claude/memory/state/current-triage.json"
if [ -f "$TRIAGE_FILE" ]; then
  LANE=$(grep -o '"lane"[[:space:]]*:[[:space:]]*"[^"]*"' "$TRIAGE_FILE" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  [ -n "$LANE" ] && CTX="${CTX}\n## Lane: ${LANE}\n"
fi

# ---------------------------------------------------------------------------
# Config injection for subagent
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
# v4.1 — cap output per DEVCO_SUBAGENT_INIT_MAX_CHARS env var
CTX_CAPPED=$(cap_context "$CTX" 6000 "DEVCO_SUBAGENT_INIT_MAX_CHARS" 2>/dev/null || echo "$CTX")
CTX_ESCAPED="$(printf '%s' "$CTX_CAPPED" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')"

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}' "$CTX_ESCAPED"
exit 0
