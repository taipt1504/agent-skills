#!/usr/bin/env bash
# =============================================================================
# workflow-tracker.sh — PostToolUse Bash Workflow Activity Tracker (v3.1)
# =============================================================================
# Detects workflow-relevant Bash commands (build, test, compile) and updates
# activity counters in .claude/workflow-state.json.
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

# Only proceed if workflow-state.json exists
[ -f "$WORKFLOW_FILE" ] || exit 0

# Detect activity type
ACTIVITY=""
if echo "$COMMAND" | grep -qE '(\.\/)?gradlew?\s+build|gradle\s+build'; then
  ACTIVITY="BUILD"
elif echo "$COMMAND" | grep -qE '(\.\/)?gradlew?\s+test|gradle\s+test'; then
  ACTIVITY="VERIFY"
elif echo "$COMMAND" | grep -qE '(\.\/)?gradlew?\s+compileJava|gradle\s+compileJava'; then
  ACTIVITY="COMPILE"
fi

[ -z "$ACTIVITY" ] && exit 0

# Update workflow-state.json — increment counter and update timestamp
ACTIVITY="$ACTIVITY" WORKFLOW_FILE="$WORKFLOW_FILE" python3 -c "
import json, os, datetime

wf_path = os.environ['WORKFLOW_FILE']
activity = os.environ['ACTIVITY']

with open(wf_path) as f:
    state = json.load(f)

counters = state.setdefault('activity_counters', {})
counters[activity] = counters.get(activity, 0) + 1

timestamps = state.setdefault('activity_timestamps', {})
timestamps[activity] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

with open(wf_path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
" 2>/dev/null || true

exit 0
