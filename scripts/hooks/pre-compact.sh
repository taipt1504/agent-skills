#!/usr/bin/env bash
#
# PreCompact Hook - Save state before context compaction
# Cross-platform (macOS, Linux)
#
# Runs before Claude compacts context, giving you a chance to
# preserve important state that might get lost in summarization.
#

# Resolve project root (works in worktrees too)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

# Get directories and timestamps (relative to project root)
SESSIONS_DIR=".claude/sessions"
COMPACTION_LOG="$SESSIONS_DIR/compaction-log.txt"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
TIME_STR=$(date "+%H:%M")

# Ensure directory exists
mkdir -p "$SESSIONS_DIR"

# Log compaction event
echo "[$TIMESTAMP] Context compaction triggered" >> "$COMPACTION_LOG"

# Find active session file and note compaction
ACTIVE_SESSION=$(find "$SESSIONS_DIR" -name "*.tmp" -type f 2>/dev/null | sort -r | head -1)

if [ -n "$ACTIVE_SESSION" ] && [ -f "$ACTIVE_SESSION" ]; then
    echo "" >> "$ACTIVE_SESSION"
    echo "---" >> "$ACTIVE_SESSION"
    echo "**[Compaction occurred at $TIME_STR]** - Context was summarized" >> "$ACTIVE_SESSION"
fi

echo "[PreCompact] State saved before compaction" >&2

exit 0
