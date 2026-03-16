#!/usr/bin/env bash
# =============================================================================
# cost-tracker.sh — Token usage and cost tracking hook
# =============================================================================
#
# Reads stdin JSON for token usage data, appends JSONL to cost log,
# estimates cost per model tier, and warns when daily cost exceeds threshold.
#
# Fires on: Stop (async)
# Input: JSON from stdin (tool result with token data)
# Output: warnings to stderr
#
# Environment:
#   COST_DAILY_THRESHOLD  — Daily cost warning threshold in USD (default: 5.00)
#   CLAUDE_SESSION_ID     — Session identifier
# =============================================================================

# NOTE: No set -euo pipefail — hooks must ALWAYS exit 0.

source "$(dirname "$0")/run-with-flags.sh" "cost-tracker" || exit 0

log() { echo "[CostTracker] $*" >&2; }

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
COST_LOG="$PROJECT_ROOT/.claude/sessions/cost-log.jsonl"
DAILY_THRESHOLD="${COST_DAILY_THRESHOLD:-5.00}"
TODAY="$(date +%Y-%m-%d)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

mkdir -p "$(dirname "$COST_LOG")"

# Read stdin (pass through for hook chain)
INPUT=""
if [ ! -t 0 ]; then
  INPUT="$(cat)"
  if [ -n "$INPUT" ]; then
    echo "$INPUT"
  fi
fi

# Try to extract token counts from input JSON
INPUT_TOKENS=0
OUTPUT_TOKENS=0

if [ -n "$INPUT" ] && command -v python3 &>/dev/null; then
  TOKENS="$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    usage = data.get('usage', data.get('token_usage', {}))
    inp = usage.get('input_tokens', usage.get('prompt_tokens', 0))
    out = usage.get('output_tokens', usage.get('completion_tokens', 0))
    print(f'{inp} {out}')
except:
    print('0 0')
" 2>/dev/null || echo "0 0")"
  INPUT_TOKENS="${TOKENS%% *}"
  OUTPUT_TOKENS="${TOKENS##* }"
fi

# Cost estimation per 1M tokens (approximate pricing)
# opus: $15/1M input, $75/1M output
# sonnet: $3/1M input, $15/1M output
# haiku: $0.25/1M input, $1.25/1M output
# Default to sonnet pricing as most common; override via env vars
COST_PER_INPUT="${COST_PER_INPUT_PER_1M:-3}"
COST_PER_OUTPUT="${COST_PER_OUTPUT_PER_1M:-15}"

# Calculate estimated cost in millicents for precision
if [ "$INPUT_TOKENS" -gt 0 ] || [ "$OUTPUT_TOKENS" -gt 0 ]; then
  # Use bc if available, otherwise python3
  if command -v bc &>/dev/null; then
    EST_COST="$(echo "scale=6; ($INPUT_TOKENS * $COST_PER_INPUT + $OUTPUT_TOKENS * $COST_PER_OUTPUT) / 1000000" | bc 2>/dev/null || echo "0")"
  elif command -v python3 &>/dev/null; then
    EST_COST="$(python3 -c "print(f'{($INPUT_TOKENS * $COST_PER_INPUT + $OUTPUT_TOKENS * $COST_PER_OUTPUT) / 1000000:.6f}')" 2>/dev/null || echo "0")"
  else
    EST_COST="0"
  fi
else
  EST_COST="0"
fi

# Append JSONL entry
echo "{\"timestamp\":\"$TIMESTAMP\",\"date\":\"$TODAY\",\"session_id\":\"$SESSION_ID\",\"input_tokens\":$INPUT_TOKENS,\"output_tokens\":$OUTPUT_TOKENS,\"estimated_cost_usd\":$EST_COST}" >> "$COST_LOG"

# Check daily total and warn if threshold exceeded
if [ -f "$COST_LOG" ] && command -v python3 &>/dev/null; then
  DAILY_TOTAL="$(python3 -c "
import json, sys
total = 0.0
today = '$TODAY'
try:
    with open('$COST_LOG') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get('date') == today:
                    total += float(entry.get('estimated_cost_usd', 0))
            except:
                continue
    print(f'{total:.4f}')
except:
    print('0')
" 2>/dev/null || echo "0")"

  # Compare with threshold
  OVER_THRESHOLD="$(python3 -c "print('yes' if float('$DAILY_TOTAL') >= float('$DAILY_THRESHOLD') else 'no')" 2>/dev/null || echo "no")"

  if [ "$OVER_THRESHOLD" = "yes" ]; then
    log "WARNING: Daily cost estimate \$$DAILY_TOTAL exceeds threshold \$$DAILY_THRESHOLD"
    log "Consider using sonnet/haiku models for routine tasks"
  fi
fi

exit 0
