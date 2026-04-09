#!/usr/bin/env bash
# =============================================================================
# team-spawn-evaluator.sh — PostToolUse Multi-Agent Spawn Evaluator (v3.3)
# =============================================================================
# Evaluates whether to suggest multi-agent spawning after BUILD phase entry.
# Supports TWO modes (configured in devco-config.json → team.mode):
#
#   "subagent" (default, stable):
#     Uses Agent tool with isolation: "worktree" for safe parallel file edits.
#     Agents report results to parent only. No inter-agent communication.
#     Best for: independent TDD modules, parallel implementation.
#
#   "team" (experimental):
#     Uses TeamCreate + TaskCreate for shared task list + SendMessage.
#     Agents can message each other directly. Shared working directory.
#     Best for: interdependent work requiring interface negotiation.
#     Requires: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
#
# Non-blocking: always exits 0. Emits additionalContext with spawn template.
# Fires on: PostToolUse (Bash) — async, timeout 10
# =============================================================================

trap 'exit 0' ERR

source "$(dirname "$0")/run-with-flags.sh" "team-spawn-evaluator" || exit 0

DATA=$(cat)

# Extract bash command from tool input
BASH_CMD=$(echo "$DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('input','').get('command',''))" 2>/dev/null || echo "")

# Check if this is a /build invocation or BUILD phase transition
IS_BUILD_RELEVANT=false

if echo "$BASH_CMD" | grep -qiE '\/build(\s|$)'; then
  IS_BUILD_RELEVANT=true
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
WORKFLOW_FILE="$PROJECT_ROOT/.claude/workflow-state.json"

if [ -f "$WORKFLOW_FILE" ]; then
  CURRENT_PHASE=$(python3 -c "import json; print(json.load(open('$WORKFLOW_FILE')).get('phase',''))" 2>/dev/null || echo "")
  if [ "$CURRENT_PHASE" = "BUILD" ]; then
    IS_BUILD_RELEVANT=true
  fi
fi

if [ "$IS_BUILD_RELEVANT" = false ]; then
  exit 0
fi

# --- Read team config ---
DEVCO_CONFIG="$PROJECT_ROOT/.claude/devco-config.json"
if [ ! -f "$DEVCO_CONFIG" ]; then
  exit 0
fi

TEAM_ENABLED=$(python3 -c "import json; print(json.load(open('$DEVCO_CONFIG')).get('team',{}).get('enabled', False))" 2>/dev/null || echo "False")
if [ "$TEAM_ENABLED" != "True" ] && [ "$TEAM_ENABLED" != "true" ]; then
  exit 0
fi

TEAM_MODE=$(python3 -c "import json; print(json.load(open('$DEVCO_CONFIG')).get('team',{}).get('mode', 'subagent'))" 2>/dev/null || echo "subagent")
IMPL_MODEL=$(python3 -c "import json; print(json.load(open('$DEVCO_CONFIG')).get('team',{}).get('roles',{}).get('implementer',{}).get('model','sonnet'))" 2>/dev/null || echo "sonnet")

# --- Read spec path and count tasks ---
if [ ! -f "$WORKFLOW_FILE" ]; then
  exit 0
fi

SPEC_PATH=$(python3 -c "import json; print(json.load(open('$WORKFLOW_FILE')).get('artifacts',{}).get('spec',''))" 2>/dev/null || echo "")

if [ -z "$SPEC_PATH" ] || [ ! -f "$SPEC_PATH" ]; then
  exit 0
fi

TASK_COUNT=$(grep -c "^### Task" "$SPEC_PATH" 2>/dev/null || echo "0")

if [ "$TASK_COUNT" -lt 2 ]; then
  exit 0
fi

# --- Build spawn template based on mode ---
if [ "$TEAM_MODE" = "team" ]; then
  # =========================================================================
  # MODE: Agent Teams (experimental)
  # Uses TeamCreate + TaskCreate + SendMessage
  # Shared working directory — partition files by ownership
  # =========================================================================
  SPAWN_MSG="AGENT TEAM RECOMMENDED (mode: team): The spec has ${TASK_COUNT} independent tasks.

Use Agent Teams for coordinated parallel execution:

**Step 1: Create the team**
\`\`\`
TeamCreate({
  team_name: \"build-{feature}\",
  description: \"TDD implementation for {feature}\"
})
\`\`\`

**Step 2: Create tasks from the spec**
For each ### Task section in the spec:
\`\`\`
TaskCreate({
  subject: \"{task title}\",
  description: \"Implement: {task description}. Spec: ${SPEC_PATH}. TDD: RED->GREEN->REFACTOR. No .block() in src/main/. No git commit.\"
})
\`\`\`

**Step 3: Spawn teammates**
For each task, spawn a teammate:
\`\`\`
Agent({
  description: \"Implement: {task title}\",
  prompt: \"You are a teammate. Read your assigned task via TaskGet. Implement using TDD. Load devco-agent-skills:coding-standards. Mark task completed via TaskUpdate when done.\",
  team_name: \"build-{feature}\",
  name: \"impl-{N}\",
  model: \"${IMPL_MODEL}\",
  run_in_background: true
})
\`\`\`

**Step 4: Coordinate**
- Monitor teammate progress via TaskList
- Teammates can message each other via SendMessage for interface negotiation
- After all tasks complete -> run /verify full -> /dc-review
- Clean up: TeamDelete

NOTE: Agent Teams use SHARED working directory. Partition files by ownership — each teammate should own distinct source files to avoid conflicts."

else
  # =========================================================================
  # MODE: Subagents (stable, default)
  # Uses Agent tool with isolation: "worktree"
  # Each agent gets isolated git worktree — safe parallel writes
  # =========================================================================
  SPAWN_MSG="PARALLEL SUBAGENTS RECOMMENDED (mode: subagent): The spec has ${TASK_COUNT} independent tasks.

Use Subagents with worktree isolation for safe parallel execution:

For each ### Task section in the spec, spawn an independent agent:
\`\`\`
Agent({
  description: \"Implement: {task title}\",
  prompt: \"You are an implementer. Your task: {task description}. Spec: ${SPEC_PATH}. Follow TDD: RED->GREEN->REFACTOR. Load devco-agent-skills:coding-standards and devco-agent-skills:testing-workflow. No .block() in src/main/. No git commit.\",
  model: \"${IMPL_MODEL}\",
  isolation: \"worktree\",
  run_in_background: true
})
\`\`\`

**Key properties:**
- \`isolation: \"worktree\"\` — each agent gets an isolated git worktree (safe parallel writes)
- \`run_in_background: true\` — all agents run concurrently
- Agents report results to you (parent) only — no inter-agent communication
- After all agents complete -> merge worktree changes -> run /verify full -> /dc-review

NOTE: Subagents are INDEPENDENT. Each works in its own worktree copy. They cannot communicate with each other. Use this mode for tasks that don't need to negotiate interfaces."

fi

SPAWN_MSG_ESCAPED=$(echo "$SPAWN_MSG" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read())[1:-1])" 2>/dev/null || echo "$SPAWN_MSG" | sed 's/"/\\"/g' | tr '\n' ' ')

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$SPAWN_MSG_ESCAPED"

exit 0
