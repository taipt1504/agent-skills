#!/usr/bin/env bash
# =============================================================================
# pre-compact.sh — Pre-Compaction State Checkpoint (v3.0)
# =============================================================================
# Saves active files and session state before context compaction.
# Fires on: PreCompact (strict profile only)
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "pre-compact" || exit 0

exec 1>&2
trap 'exit 0' ERR

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true
PROJECT_NAME="$(basename "$PROJECT_ROOT")"

SESSIONS_DIR=".claude/sessions"
COMPACTION_LOG="$SESSIONS_DIR/compaction-log.txt"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p "$SESSIONS_DIR"

# Log compaction event
echo "[$TIMESTAMP] Context compaction triggered" >> "$COMPACTION_LOG"

# Find active session
ACTIVE_SESSION=$(find "$SESSIONS_DIR" -name "*.tmp" -type f 2>/dev/null | sort -r | head -1)
SESSION_ID="unknown"

if [ -n "$ACTIVE_SESSION" ] && [ -f "$ACTIVE_SESSION" ]; then
  SESSION_ID="$(basename "$ACTIVE_SESSION" .tmp)"
  echo -e "\n---\n**[Compaction at $(date +%H:%M)]** — Context summarized" >> "$ACTIVE_SESSION"
fi

# Collect active files from git diff
ACTIVE_FILES="[]"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  STAGED="$(git diff --cached --name-only 2>/dev/null || true)"
  MODIFIED="$(git diff --name-only 2>/dev/null || true)"
  ACTIVE_FILES=$(python3 -c "
import json
files = set()
for line in '''$STAGED
$MODIFIED'''.strip().splitlines():
    line = line.strip()
    if line:
        files.add(line)
print(json.dumps(sorted(list(files))[:50]))
" 2>/dev/null) || ACTIVE_FILES="[]"
fi

# Save recovery file
RECOVERY_FILE="$SESSIONS_DIR/pre-compact-${SESSION_ID}.json"
python3 -c "
import json
recovery = {
    'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'session': '$SESSION_ID',
    'project': '$PROJECT_NAME',
    'active_files': $ACTIVE_FILES,
    'compaction_marker': True
}
with open('$RECOVERY_FILE', 'w') as f:
    json.dump(recovery, f, indent=2)
    f.write('\n')
" 2>/dev/null || true

ACTIVE_COUNT=$(echo "$ACTIVE_FILES" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
echo "[PreCompact] Saved ${ACTIVE_COUNT} active files to ${RECOVERY_FILE}"

exit 0
