#!/usr/bin/env bash
#
# SessionEnd Hook - Persist session state when session ends
# Cross-platform (macOS, Linux)
#
# Runs when Claude session ends. Creates/updates session log file
# with timestamp for continuity tracking.
#

# Resolve project root (works in worktrees too)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

# Get directories and timestamps (relative to project root)
SESSIONS_DIR=".claude/sessions"
TODAY=$(date +%Y-%m-%d)
CURRENT_TIME=$(date +%H:%M)
SHORT_ID="${CLAUDE_SESSION_ID:-$(echo $$ | tail -c 5)}"
SESSION_FILE="$SESSIONS_DIR/${TODAY}-${SHORT_ID}-session.tmp"

# Ensure directory exists
mkdir -p "$SESSIONS_DIR"

# Update or create session file
if [ -f "$SESSION_FILE" ]; then
    # Update last modified time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/\*\*Last Updated:\*\*.*/\*\*Last Updated:\*\* $CURRENT_TIME/" "$SESSION_FILE"
    else
        sed -i "s/\*\*Last Updated:\*\*.*/\*\*Last Updated:\*\* $CURRENT_TIME/" "$SESSION_FILE"
    fi
    echo "[SessionEnd] Updated session file: $SESSION_FILE" >&2
else
    # Create new session file
    cat > "$SESSION_FILE" << EOF
# Session: $TODAY
**Date:** $TODAY
**Started:** $CURRENT_TIME
**Last Updated:** $CURRENT_TIME

---

## Current State

[Session context goes here]

### Completed
- [ ]

### In Progress
- [ ]

### Notes for Next Session
-

### Context to Load
\`\`\`
[relevant files]
\`\`\`
EOF
    echo "[SessionEnd] Created session file: $SESSION_FILE" >&2
fi

exit 0
