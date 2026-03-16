#!/usr/bin/env bash
#
# Strategic Compact Suggester
# Cross-platform (macOS, Linux)
#
# Runs on PreToolUse to suggest manual compaction at logical intervals
#
# Why manual over auto-compact:
# - Auto-compact happens at arbitrary points, often mid-task
# - Strategic compacting preserves context through logical phases
# - Compact after exploration, before execution
# - Compact after completing a milestone, before starting next
#

# Profile gate
source "$(dirname "$0")/run-with-flags.sh" "suggest-compact" || exit 0

# Resolve project root (works in worktrees too)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

# Session tracking
SESSION_ID="${CLAUDE_SESSION_ID:-$(echo "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" | cksum | cut -d' ' -f1)}"
TEMP_DIR="${TMPDIR:-/tmp}"
COUNTER_FILE="$TEMP_DIR/claude-tool-count-$SESSION_ID"
THRESHOLD="${COMPACT_THRESHOLD:-50}"

# Read or initialize counter
if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE")
    COUNT=$((COUNT + 1))
else
    COUNT=1
fi

# Save updated count
echo "$COUNT" > "$COUNTER_FILE"

# Suggest compact after threshold tool calls
if [ "$COUNT" -eq "$THRESHOLD" ]; then
    echo "[StrategicCompact] $THRESHOLD tool calls reached - consider /compact if transitioning phases" >&2
fi

# Suggest at regular intervals after threshold
if [ "$COUNT" -gt "$THRESHOLD" ] && [ $((COUNT % 25)) -eq 0 ]; then
    echo "[StrategicCompact] $COUNT tool calls - good checkpoint for /compact if context is stale" >&2
fi

exit 0
