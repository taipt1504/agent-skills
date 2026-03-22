#!/usr/bin/env bash
# =============================================================================
# session-save.sh — Session End Hook (v3.0)
# =============================================================================
# Saves session summary to L2 memory, persists file list, extracts patterns.
# Replaces: session-end.sh + evaluate-session.sh + cost-tracker.sh
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "session-save" || exit 0

log()  { echo "[SessionSave] $*" >&2; }
warn() { echo "[SessionSave] WARNING: $*" >&2; }

# Read stdin immediately
STDIN_DATA=""
[ ! -t 0 ] && STDIN_DATA="$(cat 2>/dev/null || true)"

PROJECT_ROOT="${PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$PROJECT_ROOT" 2>/dev/null || true
PROJECT_NAME="$(basename "$(pwd)")"

TODAY="$(date +%Y-%m-%d)"
CURRENT_TIME="$(date +%H:%M)"
CURRENT_EPOCH="$(date +%s)"

# Short ID
if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
  SHORT_ID="${CLAUDE_SESSION_ID: -6}"
else
  SHORT_ID="$(printf '%05d' $$)"
fi

# Idempotency check (stored in memory dir)
MARKER_DIR=".claude/memory/sessions"
mkdir -p "$MARKER_DIR"
MARKER_FILE="$MARKER_DIR/.written-${SHORT_ID}"
[ -f "$MARKER_FILE" ] && { log "Already written — skipping"; exit 0; }

# --- Git context ---
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
FILES_FROM_UNCOMMITTED="$(git diff --name-only HEAD 2>/dev/null || true)"
FILES_FROM_STAGED="$(git diff --cached --name-only 2>/dev/null || true)"
FILES_FROM_COMMITS="$(git log --since="$TODAY" --name-only --pretty=format: 2>/dev/null | sort -u || true)"
FILES_MODIFIED="$(printf '%s\n%s\n%s' "$FILES_FROM_UNCOMMITTED" "$FILES_FROM_STAGED" "$FILES_FROM_COMMITS" | grep -v '^$' | sort -u || true)"
TESTS_MODIFIED="$(echo "$FILES_MODIFIED" | grep -iE '(test[_.]|_test\.|\.test\.|\.spec\.|tests/)' || true)"

UNCOMMITTED_FILES="$(git status --porcelain 2>/dev/null | awk '{print $2}' || true)"
HAS_UNCOMMITTED=false
[ -n "$UNCOMMITTED_FILES" ] && HAS_UNCOMMITTED=true

# --- Transcript analysis ---
TRANSCRIPT_PATH="${CLAUDE_TRANSCRIPT_PATH:-}"
USER_MESSAGES=0
TOOL_CALLS=0

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  USER_MESSAGES="$(grep -cE '"type":"user"|"role":"user"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)"
  TOOL_CALLS="$(grep -cE '"type":"tool_use"|"type":"tool_result"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)"
fi

FILE_COUNT="$(echo "$FILES_MODIFIED" | grep -c . 2>/dev/null || echo 0)"
TEST_COUNT="$(echo "$TESTS_MODIFIED" | grep -c . 2>/dev/null || echo 0)"
DIFF_STAT="$(git diff --stat HEAD 2>/dev/null | tail -1 || true)"

SUMMARY_TEXT="Session on ${TODAY} (${BRANCH}): ${USER_MESSAGES} user messages, ${TOOL_CALLS} tool calls, ${FILE_COUNT} files modified, ${TEST_COUNT} tests touched."
[ -n "$DIFF_STAT" ] && SUMMARY_TEXT="${SUMMARY_TEXT} Changes: ${DIFF_STAT}"

# --- Write to structured memory ---
WRITE_SESSION="$(dirname "$0")/../memory/write-session.sh"
[ -x "$WRITE_SESSION" ] || WRITE_SESSION="${CLAUDE_PLUGIN_ROOT:-}/scripts/memory/write-session.sh"
if [ -x "$WRITE_SESSION" ]; then
  bash "$WRITE_SESSION" "${TODAY}-${SHORT_ID}" "$BRANCH" "$FILE_COUNT" "$USER_MESSAGES" "$TOOL_CALLS" "$SUMMARY_TEXT" 2>/dev/null || true
fi

# --- Update active work context ---
ACTIVE_WORK_FILE="$PROJECT_ROOT/.claude/memory/context/active-work.json"
if [ -d "$PROJECT_ROOT/.claude/memory/context" ]; then
  RECENT_COMMIT="$(git log -1 --oneline 2>/dev/null || echo "none")"
  cat > "$ACTIVE_WORK_FILE" <<EOF
{"current_task":"$BRANCH","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","notes":["Last commit: $RECENT_COMMIT"]}
EOF
fi

# --- Debug knowledge base (append error patterns) ---
DEBUG_KB=".claude/memory/debug-knowledge.md"
if [ -f "$DEBUG_KB" ] && [ -n "$FILES_MODIFIED" ]; then
  # Check if any modified files suggest bug fixes (commit messages with "fix")
  FIX_COMMITS="$(git log --since="$TODAY" --oneline --grep="fix" 2>/dev/null | head -3 || true)"
  if [ -n "$FIX_COMMITS" ]; then
    {
      echo ""
      echo "## ${TODAY} — Fix patterns from session"
      echo "$FIX_COMMITS" | while IFS= read -r c; do
        [ -n "$c" ] && echo "- $c"
      done
    } >> "$DEBUG_KB"
    log "Debug patterns appended to debug-knowledge.md"
  fi
fi

# --- Learning signal ---
if [ "$USER_MESSAGES" -ge 10 ]; then
  SIGNALS_DIR=".claude/signals"
  mkdir -p "$SIGNALS_DIR"
  {
    echo "session_id=${CLAUDE_SESSION_ID:-$$}"
    echo "date=${TODAY}"
    echo "branch=${BRANCH}"
    echo "user_messages=${USER_MESSAGES}"
    echo "timestamp=${CURRENT_EPOCH}"
  } > "$SIGNALS_DIR/learning-${TODAY}-${SHORT_ID}.signal"
  log "Learning signal written"
fi

# Write idempotency marker
echo "$CURRENT_EPOCH" > "$MARKER_FILE"

# Warn about uncommitted changes
if [ "$HAS_UNCOMMITTED" = true ]; then
  UNCOMMITTED_COUNT="$(echo "$UNCOMMITTED_FILES" | grep -c . 2>/dev/null || echo 0)"
  warn "Uncommitted changes: ${UNCOMMITTED_COUNT} files"
fi

log "Done. Branch=${BRANCH} Messages=${USER_MESSAGES} Files=${FILE_COUNT}"
exit 0
