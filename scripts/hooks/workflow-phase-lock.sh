#!/usr/bin/env bash
# =============================================================================
# workflow-phase-lock.sh — PostToolUse Bash Exit Guard (v3.3)
# =============================================================================
# After a Bash tool use:
#   1. If a gradle build/test command succeeds while phase is BUILD:
#      → auto-set phase to VERIFY_PENDING in workflow-state.json
#   2. If phase is VERIFY_PENDING or REVIEW_PENDING:
#      → emit additionalContext warning to force the agent to run /verify or /dc-review
#   3. If /verify completes successfully (exit 0 + test results in output):
#      → auto-set phase to REVIEW_PENDING
# Fires on: PostToolUse (Bash) — async, must complete in <100ms
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "workflow-phase-lock" || exit 0

trap 'exit 0' ERR

DATA=$(cat)

# Extract command, exit code, and output using python3 (fast, available)
BASH_CMD=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('input','').get('command','') if isinstance(d.get('input',''), dict) else '')" 2>/dev/null <<< "$DATA" || echo "")
EXIT_CODE=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('exitCode',0))" 2>/dev/null <<< "$DATA" || echo "0")
TOOL_OUTPUT=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('output',''))" 2>/dev/null <<< "$DATA" || echo "")

# Skip if no command detected
[ -z "$BASH_CMD" ] && { exit 0; }

# Locate workflow-state.json
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
WORKFLOW_FILE="$PROJECT_ROOT/.claude/workflow-state.json"

# No workflow file → nothing to do
[ ! -f "$WORKFLOW_FILE" ] && exit 0

# Read current phase
CURRENT_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$WORKFLOW_FILE" | head -1 | sed 's/.*: *"//' | sed 's/".*//')

# --- CASE 1: Gradle build/test succeeded while in BUILD phase ---
# Detect a successful gradle build or test run
if echo "$BASH_CMD" | grep -qE '(\.\/)?gradlew?\s+(build|test|check)\b'; then
  if [ "$EXIT_CODE" = "0" ] && [ "$CURRENT_PHASE" = "BUILD" ]; then
    # Transition BUILD → VERIFY_PENDING
    python3 - <<PYEOF 2>/dev/null || true
import json, datetime, os

wf_path = os.environ.get('WORKFLOW_FILE', '$WORKFLOW_FILE')
with open(wf_path) as f:
    state = json.load(f)

now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

# Add BUILD to phaseHistory if not already present
history = state.setdefault('phaseHistory', [])
build_recorded = any(e.get('phase') == 'BUILD' for e in history)
if not build_recorded:
    history.append({"phase": "BUILD", "completedAt": now})

state['phase'] = 'VERIFY_PENDING'
state['verifyPendingSince'] = now

with open(wf_path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
PYEOF

    MSG="[WorkflowPhaseLock] BUILD complete — phase set to VERIFY_PENDING. You MUST run /verify full NOW before making any more code changes. This is MANDATORY — do not skip."
    MSG_ESCAPED=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$MSG_ESCAPED"
    exit 0
  fi
fi

# --- CASE 2: Emit warning if stuck in VERIFY_PENDING or REVIEW_PENDING ---
if [ "$CURRENT_PHASE" = "VERIFY_PENDING" ]; then
  # Check if /verify was just run (command contains verify or gradlew test)
  if echo "$BASH_CMD" | grep -qiE '(\/verify|gradlew\s+test|gradlew\s+build|gradlew\s+check)'; then
    # If verify command succeeded, transition to REVIEW_PENDING
    if [ "$EXIT_CODE" = "0" ]; then
      python3 - <<PYEOF 2>/dev/null || true
import json, datetime, os

wf_path = os.environ.get('WORKFLOW_FILE', '$WORKFLOW_FILE')
with open(wf_path) as f:
    state = json.load(f)

now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

history = state.setdefault('phaseHistory', [])
verify_recorded = any(e.get('phase') == 'VERIFY' for e in history)
if not verify_recorded:
    history.append({"phase": "VERIFY", "completedAt": now, "verdict": "PASS"})

state['phase'] = 'REVIEW_PENDING'
state['reviewPendingSince'] = now
state.pop('verifyPendingSince', None)

with open(wf_path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
PYEOF

      MSG="[WorkflowPhaseLock] VERIFY passed — phase set to REVIEW_PENDING. You MUST run /dc-review NOW to complete the workflow. Do NOT stop here."
      MSG_ESCAPED=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
      printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$MSG_ESCAPED"
      exit 0
    fi
  else
    # Still in VERIFY_PENDING but running unrelated commands — remind the agent
    MSG="[WorkflowPhaseLock] WARNING: Phase is VERIFY_PENDING. BUILD is complete but VERIFY+REVIEW have not run. You MUST run /verify full NOW before doing anything else."
    MSG_ESCAPED=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$MSG_ESCAPED"
    exit 0
  fi
fi

if [ "$CURRENT_PHASE" = "REVIEW_PENDING" ]; then
  # Check if /dc-review was just invoked
  if echo "$BASH_CMD" | grep -qiE '(\/dc-review|\/review)'; then
    # Pass through — dc-review will update state itself
    exit 0
  else
    # Stuck in REVIEW_PENDING — remind the agent
    MSG="[WorkflowPhaseLock] WARNING: Phase is REVIEW_PENDING. VERIFY passed but /dc-review has not run. You MUST run /dc-review NOW to complete the workflow. Do NOT stop."
    MSG_ESCAPED=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$MSG_ESCAPED"
    exit 0
  fi
fi

exit 0
