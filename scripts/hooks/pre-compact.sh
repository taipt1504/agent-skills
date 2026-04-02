#!/usr/bin/env bash
# =============================================================================
# pre-compact.sh — Pre-Compaction State Checkpoint (v3.1)
# =============================================================================
# Saves rich state (workflow phase, task, decisions, active files, compaction
# count) before context compaction for post-compact recovery.
# Fires on: PreCompact (standard+ profiles)
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

# Read workflow state (phase, task, decisions)
WORKFLOW_FILE=".claude/workflow-state.json"
PHASE="UNKNOWN"
TASK="UNKNOWN"
DECISIONS="[]"

if [ -f "$WORKFLOW_FILE" ]; then
  PHASE=$(python3 -c "import json; d=json.load(open('$WORKFLOW_FILE')); print(d.get('phase','UNKNOWN'))" 2>/dev/null) || PHASE="UNKNOWN"
  TASK=$(python3 -c "import json; d=json.load(open('$WORKFLOW_FILE')); print(d.get('task','UNKNOWN'))" 2>/dev/null) || TASK="UNKNOWN"
  DECISIONS=$(python3 -c "import json; d=json.load(open('$WORKFLOW_FILE')); print(json.dumps(d.get('decisions',[])))" 2>/dev/null) || DECISIONS="[]"
fi

# Calculate compaction count from log
COMPACTION_COUNT=$(grep -c "Context compaction triggered" "$COMPACTION_LOG" 2>/dev/null || echo 0)

# Collect active files from git diff
ACTIVE_FILES="[]"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  STAGED="$(git diff --cached --name-only 2>/dev/null || true)"
  MODIFIED="$(git diff --name-only 2>/dev/null || true)"
  ACTIVE_FILES=$(STAGED="$STAGED" MODIFIED="$MODIFIED" python3 -c "
import json, os
files = set()
for line in (os.environ.get('STAGED','') + '\n' + os.environ.get('MODIFIED','')).strip().splitlines():
    line = line.strip()
    if line:
        files.add(line)
print(json.dumps(sorted(list(files))[:50]))
" 2>/dev/null) || ACTIVE_FILES="[]"
fi

# Save recovery file
RECOVERY_FILE="$SESSIONS_DIR/pre-compact-${SESSION_ID}.json"
PHASE="$PHASE" TASK="$TASK" DECISIONS="$DECISIONS" ACTIVE_FILES="$ACTIVE_FILES" \
  COMPACTION_COUNT="$COMPACTION_COUNT" SESSION_ID="$SESSION_ID" PROJECT_NAME="$PROJECT_NAME" \
  RECOVERY_FILE="$RECOVERY_FILE" python3 -c "
import json, os, datetime

recovery = {
    'timestamp': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'session': os.environ['SESSION_ID'],
    'project': os.environ['PROJECT_NAME'],
    'phase': os.environ['PHASE'],
    'task': os.environ['TASK'],
    'decisions': json.loads(os.environ['DECISIONS']),
    'active_files': json.loads(os.environ['ACTIVE_FILES']),
    'compaction_count': int(os.environ['COMPACTION_COUNT'])
}
with open(os.environ['RECOVERY_FILE'], 'w') as f:
    json.dump(recovery, f, indent=2)
    f.write('\n')
" 2>/dev/null || true

ACTIVE_COUNT=$(echo "$ACTIVE_FILES" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
echo "[PreCompact] Saved phase=${PHASE}, task=${TASK}, ${ACTIVE_COUNT} files, compaction #${COMPACTION_COUNT} to ${RECOVERY_FILE}"

exit 0
