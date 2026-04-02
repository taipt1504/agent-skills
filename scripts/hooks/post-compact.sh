#!/usr/bin/env bash
# =============================================================================
# post-compact.sh — Post-Compaction Context Recovery (v3.1)
# =============================================================================
# Reads the pre-compact recovery file and re-injects critical context as
# additionalContext so the agent can continue seamlessly after compaction.
# Fires on: PostCompact (standard+ profiles)
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "post-compact" || exit 0

trap 'exit 0' ERR

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

SESSIONS_DIR=".claude/sessions"

# Find active session
ACTIVE_SESSION=$(find "$SESSIONS_DIR" -name "*.tmp" -type f 2>/dev/null | sort -r | head -1)
SESSION_ID="unknown"
if [ -n "$ACTIVE_SESSION" ] && [ -f "$ACTIVE_SESSION" ]; then
  SESSION_ID="$(basename "$ACTIVE_SESSION" .tmp)"
fi

RECOVERY_FILE="$SESSIONS_DIR/pre-compact-${SESSION_ID}.json"

if [ -f "$RECOVERY_FILE" ]; then
  # Read recovery data and emit additionalContext
  CONTEXT=$(RECOVERY_FILE="$RECOVERY_FILE" python3 -c "
import json, os

with open(os.environ['RECOVERY_FILE']) as f:
    r = json.load(f)

phase = r.get('phase', 'UNKNOWN')
task = r.get('task', 'UNKNOWN')
decisions = r.get('decisions', [])
files = r.get('active_files', [])
count = r.get('compaction_count', 0)

decisions_str = ', '.join(decisions) if decisions else 'none recorded'
files_str = ', '.join(files[:20]) if files else 'none tracked'

print(f'''## Context Recovery (post-compaction #{count})
- **Current Phase**: {phase}
- **Task**: {task}
- **Key Decisions**: {decisions_str}
- **Active Files**: {files_str}
- Continue from where you left off. The workflow state is in .claude/workflow-state.json''')
" 2>/dev/null)

  if [ -n "$CONTEXT" ]; then
    echo "$CONTEXT"
    echo "[PostCompact] Recovered context from ${RECOVERY_FILE}" >&2
  fi
else
  # No recovery file — emit minimal reminder
  cat <<'EOF'
## Context Recovery (post-compaction)
No pre-compact snapshot found. Check `.claude/workflow-state.json` for current workflow state.
EOF
  echo "[PostCompact] No recovery file found, emitted minimal reminder" >&2
fi

exit 0
