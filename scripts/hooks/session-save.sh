#!/usr/bin/env bash
# =============================================================================
# session-save.sh — Session End Hook
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "session-save" || exit 0

log()  { echo "[SessionSave] $*" >&2; }
warn() { echo "[SessionSave] WARNING: $*" >&2; }

PROJECT_ROOT="${PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$PROJECT_ROOT" 2>/dev/null || true

# --- Git context ---
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

UNCOMMITTED_FILES="$(git status --porcelain 2>/dev/null | awk '{print $2}' || true)"
HAS_UNCOMMITTED=false
[ -n "$UNCOMMITTED_FILES" ] && HAS_UNCOMMITTED=true

# --- Read workflow state ---
LAST_PHASE=""
LAST_TASK=""
DECISIONS_JSON="[]"
WORKFLOW_FILE="$PROJECT_ROOT/.claude/workflow-state.json"
if [ -f "$WORKFLOW_FILE" ]; then
  LAST_PHASE=$(python3 -c "import json; print(json.load(open('$WORKFLOW_FILE')).get('phase',''))" 2>/dev/null) || true
  LAST_TASK=$(python3 -c "import json; print(json.load(open('$WORKFLOW_FILE')).get('task',''))" 2>/dev/null) || true
  DECISIONS_JSON=$(python3 -c "import json; print(json.dumps(json.load(open('$WORKFLOW_FILE')).get('decisions',[])))" 2>/dev/null) || DECISIONS_JSON="[]"
fi

# --- Read session metrics ---
SESSION_METRICS_FILE="$PROJECT_ROOT/.claude/sessions/session-metrics.json"
SKILLS_USED_JSON="{}"
TOOL_CALL_COUNT=0
if [ -f "$SESSION_METRICS_FILE" ]; then
  SKILLS_USED_JSON=$(python3 -c "import json; print(json.dumps(json.load(open('$SESSION_METRICS_FILE')).get('skillUsage',{})))" 2>/dev/null) || SKILLS_USED_JSON="{}"
  TOOL_CALL_COUNT=$(python3 -c "import json; print(json.load(open('$SESSION_METRICS_FILE')).get('totalToolCalls',0))" 2>/dev/null) || TOOL_CALL_COUNT=0
fi

# --- Read build checkpoint ---
BUILD_CHECKPOINT="$PROJECT_ROOT/.claude/sessions/build-checkpoint.json"
MODIFIED_FILES_JSON="[]"
MODIFIED_COUNT=0
if [ -f "$BUILD_CHECKPOINT" ]; then
  MODIFIED_FILES_JSON=$(python3 -c "import json; print(json.dumps(json.load(open('$BUILD_CHECKPOINT')).get('modifiedFiles',[])))" 2>/dev/null) || MODIFIED_FILES_JSON="[]"
  MODIFIED_COUNT=$(python3 -c "import json; print(len(json.load(open('$BUILD_CHECKPOINT')).get('modifiedFiles',[])))" 2>/dev/null) || MODIFIED_COUNT=0
fi

# --- Read verify-fix state ---
ERRORS_FIXED_JSON="[]"
VERIFY_FIX_FILE="$PROJECT_ROOT/.claude/verify-fix-state.json"
if [ -f "$VERIFY_FIX_FILE" ]; then
  ERRORS_FIXED_JSON=$(python3 -c "import json; d=json.load(open('$VERIFY_FIX_FILE')); sigs=list(d.get('errorSignatures',{}).keys()); print(json.dumps(sigs))" 2>/dev/null) || ERRORS_FIXED_JSON="[]"
fi

# --- Compute session duration estimate ---
SESSION_START_FILE="${TMPDIR:-/tmp}/claude-session-start-${CLAUDE_SESSION_ID:-unknown}"
DURATION="unknown"
if [ -f "$SESSION_START_FILE" ]; then
  START_TS=$(cat "$SESSION_START_FILE" 2>/dev/null || echo 0)
  NOW_TS=$(date +%s 2>/dev/null || echo 0)
  if [ "$START_TS" -gt 0 ] && [ "$NOW_TS" -gt 0 ]; then
    ELAPSED=$(( NOW_TS - START_TS ))
    DURATION="${ELAPSED}s"
  fi
fi

# --- Write session-summary.json (NEW — bidirectional memory) ---
SESSIONS_DIR="$PROJECT_ROOT/.claude/sessions"
mkdir -p "$SESSIONS_DIR" 2>/dev/null || true
SESSION_SUMMARY_FILE="$SESSIONS_DIR/session-summary.json"

LAST_PHASE="${LAST_PHASE:-}" LAST_TASK="${LAST_TASK:-}" \
  DECISIONS_JSON="$DECISIONS_JSON" SKILLS_USED_JSON="$SKILLS_USED_JSON" \
  MODIFIED_FILES_JSON="$MODIFIED_FILES_JSON" ERRORS_FIXED_JSON="$ERRORS_FIXED_JSON" \
  TOOL_CALL_COUNT="$TOOL_CALL_COUNT" DURATION="$DURATION" \
  SESSION_SUMMARY_FILE="$SESSION_SUMMARY_FILE" python3 -c "
import json, os, datetime

summary = {
    'savedAt': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'task': os.environ.get('LAST_TASK', '') or None,
    'phase': os.environ.get('LAST_PHASE', '') or None,
    'decisions': json.loads(os.environ.get('DECISIONS_JSON', '[]')),
    'skillsUsed': json.loads(os.environ.get('SKILLS_USED_JSON', '{}')),
    'filesModified': json.loads(os.environ.get('MODIFIED_FILES_JSON', '[]')),
    'errorsFixed': json.loads(os.environ.get('ERRORS_FIXED_JSON', '[]')),
    'toolCallCount': int(os.environ.get('TOOL_CALL_COUNT', '0') or 0),
    'duration': os.environ.get('DURATION', 'unknown'),
}

with open(os.environ['SESSION_SUMMARY_FILE'], 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
print('ok')
" 2>/dev/null && log "Session summary written → $SESSION_SUMMARY_FILE" || warn "Failed to write session-summary.json"

# --- Update active work context ---
ACTIVE_WORK_FILE="$PROJECT_ROOT/.claude/memory/context/active-work.json"
if [ -d "$PROJECT_ROOT/.claude/memory/context" ]; then
  RECENT_COMMIT="$(git log -1 --oneline 2>/dev/null || echo "none")"

  LAST_PHASE="${LAST_PHASE:-}" LAST_TASK="${LAST_TASK:-}" BRANCH="$BRANCH" \
    RECENT_COMMIT="$RECENT_COMMIT" ACTIVE_WORK_FILE="$ACTIVE_WORK_FILE" python3 -c "
import json, os, datetime

data = {
    'current_task': os.environ['BRANCH'],
    'started_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'notes': ['Last commit: ' + os.environ['RECENT_COMMIT']]
}
phase = os.environ.get('LAST_PHASE', '')
task = os.environ.get('LAST_TASK', '')
if phase:
    data['lastPhase'] = phase
if task:
    data['lastTask'] = task

with open(os.environ['ACTIVE_WORK_FILE'], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null || cat > "$ACTIVE_WORK_FILE" <<EOF
{"current_task":"$BRANCH","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","notes":["Last commit: $RECENT_COMMIT"]}
EOF
fi

# Warn about uncommitted changes
if [ "$HAS_UNCOMMITTED" = true ]; then
  UNCOMMITTED_COUNT="$(echo "$UNCOMMITTED_FILES" | grep -c . 2>/dev/null || echo 0)"
  warn "Uncommitted changes: ${UNCOMMITTED_COUNT} files"
fi

# --- Instinct candidate extraction (auto-extract) ---
INSTINCTS_DIR="${PROJECT_ROOT}/.claude/instincts/personal"

# Use tool call count from session metrics (already collected for session-summary)
# Fall back to tmp file counter for backwards compatibility
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TOOL_COUNT_FILE="${TMPDIR:-/tmp}/claude-tool-count-${SESSION_ID}"
TOOL_COUNT="$TOOL_CALL_COUNT"
if [ "$TOOL_COUNT" -eq 0 ] && [ -f "$TOOL_COUNT_FILE" ]; then
  TOOL_COUNT=$(cat "$TOOL_COUNT_FILE" 2>/dev/null || echo 0)
fi

# Only extract if instincts dir exists (created by /dc-setup or /meta)
if [ -d "$INSTINCTS_DIR" ]; then
  # Log session activity metadata
  INSTINCT_META="${INSTINCTS_DIR}/.session-meta-$(date +%s).json"

  # Use already-collected counts from session-summary block above
  # (MODIFIED_COUNT and BUILD_CHECKPOINT are already set)

  cat > "$INSTINCT_META" << INSTINCT_EOF
{
  "sessionEnd": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "branch": "${BRANCH}",
  "toolCalls": ${TOOL_COUNT},
  "modifiedFiles": ${MODIFIED_COUNT},
  "uncommittedFiles": ${UNCOMMITTED_COUNT:-0},
  "project": "$(basename "$PROJECT_ROOT")",
  "autoExtract": true
}
INSTINCT_EOF

  # --- AUTO-EXTRACT TRIGGER ---
  # Harness Engineering principle: Learning system must be autonomous.
  # Trigger auto-extraction when session had significant activity:
  #   - >20 tool calls AND >3 file changes
  # Emit additionalContext prompting agent to extract patterns before exit
  if [ "$TOOL_COUNT" -gt 20 ] && [ "$MODIFIED_COUNT" -gt 3 ]; then
    log "Auto-extract triggered: ${TOOL_COUNT} calls, ${MODIFIED_COUNT} files modified"
    # Write signal file for next session to detect and offer extraction
    cat > "${INSTINCTS_DIR}/.auto-extract-pending.json" << EXTRACT_EOF
{
  "triggeredAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "branch": "${BRANCH}",
  "toolCalls": ${TOOL_COUNT},
  "modifiedFiles": ${MODIFIED_COUNT},
  "reason": "High activity session — patterns may be worth extracting",
  "action": "Run /meta learn extract on next session start to capture patterns"
}
EXTRACT_EOF
  fi

  log "Instinct session metadata saved (autoExtract: toolCalls=${TOOL_COUNT}, files=${MODIFIED_COUNT})"
fi

# --- Reset build checkpoint (mark inactive) ---
if [ -f "${PROJECT_ROOT}/.claude/sessions/build-checkpoint.json" ]; then
  python3 -c "
import json
try:
    with open('${PROJECT_ROOT}/.claude/sessions/build-checkpoint.json') as f:
        cp = json.load(f)
    cp['active'] = False
    cp['sessionEndedAt'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    with open('${PROJECT_ROOT}/.claude/sessions/build-checkpoint.json', 'w') as f:
        json.dump(cp, f, indent=2)
except:
    pass
" 2>/dev/null || true
fi

log "Done. Branch=${BRANCH}"
exit 0
