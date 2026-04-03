#!/bin/bash
# Hook: observability-trace
# Purpose: Record structured execution traces for all tool uses
# Trigger: PostToolUse (fires after tool execution)
# Performance: <50ms, append-only, minimal overhead

set -o pipefail
trap 'echo "[ObservabilityTrace] Error: $?" >&2; exit 0' ERR  # Graceful error handling - never block tool execution

# Source profile gating (project convention)
source "$(dirname "$0")/run-with-flags.sh" "observability-trace" || exit 0

# Setup tracing infrastructure
SESSION_ID="${SESSION_ID:-$(uuidgen 2>/dev/null || echo "unknown")}"
SESSION_ID="${SESSION_ID:0:8}"  # Truncate for brevity
TRACE_DIR=".claude/sessions"
TRACE_FILE="$TRACE_DIR/execution-trace.jsonl"
METRICS_FILE="$TRACE_DIR/session-metrics.json"

# Ensure trace file and directory exist
mkdir -p "$TRACE_DIR" 2>/dev/null || true
touch "$TRACE_FILE"
touch "$METRICS_FILE"

# Capture timing
START_TIME=$(date +%s%N)
TS=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Extract tool metadata from environment variables set by Claude Code
TOOL_NAME="${TOOL_NAME:-unknown}"
FILE_PATH="${FILE_PATH:-}"
SKILL="${SKILL:-untagged}"
PHASE="${PHASE:-UNKNOWN}"
EXIT_CODE="${EXIT_CODE:-0}"
DURATION_MS="${DURATION_MS:-}"

# Determine status from exit code
STATUS="ok"
[[ "$EXIT_CODE" != "0" ]] && STATUS="error"

# Parse tool_result from stdin if available (max 500B summary)
INPUT_SUMMARY=""
if [[ -n "$TOOL_RESULT" ]]; then
  INPUT_SUMMARY=$(echo "$TOOL_RESULT" | head -c 200 | sed 's/"//g' | sed 's/\x00//g')
fi

# Calculate duration if not provided
if [[ -z "$DURATION_MS" ]]; then
  END_TIME=$(date +%s%N)
  DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
  [[ $DURATION_MS -lt 0 ]] && DURATION_MS=0
fi

# Append trace entry (append-only, one line)
{
  python3 -c "
import json
import sys
entry = {
    'ts': '$TS',
    'tool': '$TOOL_NAME',
    'file': '${FILE_PATH}',
    'skill': '$SKILL',
    'phase': '$PHASE',
    'duration_ms': $DURATION_MS,
    'status': '$STATUS',
    'session': '$SESSION_ID'
}
print(json.dumps(entry, separators=(',', ':')))
" >> "$TRACE_FILE" 2>/dev/null || true
} &

# Update session metrics (atomic JSON merge)
{
  python3 << 'PYTHON_END' "$METRICS_FILE" "$TOOL_NAME" "$SKILL" "$PHASE" "$STATUS" 2>/dev/null || true
import json
import sys
from pathlib import Path

metrics_file = sys.argv[1]
tool = sys.argv[2]
skill = sys.argv[3]
phase = sys.argv[4]
status = sys.argv[5]

try:
  with open(metrics_file, 'r') as f:
    metrics = json.load(f)
except:
  metrics = {
    'sessionId': sys.argv[6] if len(sys.argv) > 6 else 'unknown',
    'startedAt': sys.argv[7] if len(sys.argv) > 7 else '',
    'toolCalls': {}, 'skillUsage': {}, 'phaseTime': {},
    'qualityGateViolations': {'CRITICAL': 0, 'HIGH': 0},
    'verifyAttempts': 0, 'totalToolCalls': 0
  }

metrics['toolCalls'][tool] = metrics['toolCalls'].get(tool, 0) + 1
metrics['skillUsage'][skill] = metrics['skillUsage'].get(skill, 0) + 1
metrics['totalToolCalls'] = metrics['totalToolCalls'] + 1

with open(metrics_file, 'w') as f:
  json.dump(metrics, f)
PYTHON_END
} &

wait 2>/dev/null || true
exit 0
