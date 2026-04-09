#!/usr/bin/env bash
# =============================================================================
# workflow-tracker.sh — PostToolUse Bash Workflow Activity Tracker (v3.3)
# =============================================================================
# Detects workflow-relevant Bash commands (build, test, compile) and updates
# activity counters in .claude/workflow-state.json.
# Also implements state machine logic: detects /plan, /spec, /build, /verify,
# /dc-review command patterns and transitions phase accordingly.
# Valid phases: IDLE, PLAN, PLAN_APPROVED, SPEC, SPEC_APPROVED, BUILD,
#               VERIFY_PENDING, VERIFY, REVIEW_PENDING, REVIEW, COMPLETE
# Fires on: PostToolUse (Bash) — async, must complete in <100ms
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "workflow-tracker" || exit 0

trap 'exit 0' ERR

# Read tool input from stdin
DATA=$(cat)

# Extract command from Bash tool input
COMMAND=$(echo "$DATA" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

[ -z "$COMMAND" ] && exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
WORKFLOW_FILE="$PROJECT_ROOT/.claude/workflow-state.json"

# Create workflow-state.json if missing (hook-enforced, not prompt-dependent)
if [ ! -f "$WORKFLOW_FILE" ]; then
  mkdir -p "$(dirname "$WORKFLOW_FILE")" 2>/dev/null || true
  cat > "$WORKFLOW_FILE" <<WF_EOF
{
  "phase": "IDLE",
  "task": null,
  "startedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phaseHistory": [],
  "decisions": [],
  "artifacts": {},
  "autoTransition": true,
  "retryCount": 0
}
WF_EOF
fi

# Read current phase for state machine transitions
CURRENT_PHASE=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$WORKFLOW_FILE" | head -1 | sed 's/.*: *"//' | sed 's/".*//')

# --- State machine: detect phase-transition commands ---
# These detect slash commands invoked via Bash (e.g., echo /plan, bash -c "/plan ...")
# or direct mentions in the command string.
NEW_PHASE=""

if echo "$COMMAND" | grep -qiE '\/plan(\s|$)'; then
  # /plan only transitions from IDLE or COMPLETE
  if [ "$CURRENT_PHASE" = "IDLE" ] || [ "$CURRENT_PHASE" = "COMPLETE" ] || [ -z "$CURRENT_PHASE" ]; then
    NEW_PHASE="PLAN"
  fi
elif echo "$COMMAND" | grep -qiE '\/spec(\s|$)'; then
  # /spec only valid after PLAN approved
  if [ "$CURRENT_PHASE" = "PLAN" ] || [ "$CURRENT_PHASE" = "PLAN_APPROVED" ]; then
    NEW_PHASE="SPEC"
  fi
elif echo "$COMMAND" | grep -qiE '\/build(\s|$|-)' && ! echo "$COMMAND" | grep -qiE '\/build-fix'; then
  # /build only valid after SPEC approved
  if [ "$CURRENT_PHASE" = "SPEC" ] || [ "$CURRENT_PHASE" = "SPEC_APPROVED" ]; then
    NEW_PHASE="BUILD"
  fi
elif echo "$COMMAND" | grep -qiE '\/verify(\s|$)'; then
  # /verify transitions from BUILD or VERIFY_PENDING
  if [ "$CURRENT_PHASE" = "BUILD" ] || [ "$CURRENT_PHASE" = "VERIFY_PENDING" ]; then
    NEW_PHASE="VERIFY"
  fi
elif echo "$COMMAND" | grep -qiE '\/(dc-review|review)(\s|$)'; then
  # /dc-review or /review transitions from VERIFY or REVIEW_PENDING
  if [ "$CURRENT_PHASE" = "VERIFY" ] || [ "$CURRENT_PHASE" = "REVIEW_PENDING" ]; then
    NEW_PHASE="REVIEW"
  fi
fi

# Detect activity type for counter tracking
ACTIVITY=""
if echo "$COMMAND" | grep -qE '(\.\/)?gradlew?\s+build|gradle\s+build'; then
  ACTIVITY="BUILD"
elif echo "$COMMAND" | grep -qE '(\.\/)?gradlew?\s+test|gradle\s+test'; then
  ACTIVITY="VERIFY"
elif echo "$COMMAND" | grep -qE '(\.\/)?gradlew?\s+compileJava|gradle\s+compileJava'; then
  ACTIVITY="COMPILE"
fi

# Skip if nothing to update
if [ -z "$ACTIVITY" ] && [ -z "$NEW_PHASE" ]; then
  exit 0
fi

# Update workflow-state.json — increment counter, update timestamp, and apply state transition
NEW_PHASE="$NEW_PHASE" ACTIVITY="${ACTIVITY:-}" WORKFLOW_FILE="$WORKFLOW_FILE" python3 -c "
import json, os, datetime

wf_path = os.environ['WORKFLOW_FILE']
activity = os.environ.get('ACTIVITY', '')
new_phase = os.environ.get('NEW_PHASE', '')

with open(wf_path) as f:
    state = json.load(f)

now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

# Update activity counters
if activity:
    counters = state.setdefault('activity_counters', {})
    counters[activity] = counters.get(activity, 0) + 1
    timestamps = state.setdefault('activity_timestamps', {})
    timestamps[activity] = now

# Apply state transition
if new_phase:
    old_phase = state.get('phase', 'IDLE')
    # Record current phase in history before transitioning
    history = state.setdefault('phaseHistory', [])
    already_recorded = any(e.get('phase') == old_phase for e in history)
    if not already_recorded and old_phase not in ('IDLE', 'COMPLETE', ''):
        history.append({'phase': old_phase, 'completedAt': now})
    state['phase'] = new_phase
    state.setdefault('phaseTransitions', []).append({
        'from': old_phase,
        'to': new_phase,
        'at': now
    })

with open(wf_path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
" 2>/dev/null || true

exit 0
