#!/usr/bin/env bash
# ============================================================================
# session-end.sh — Production SessionEnd Hook
# ============================================================================
#
# Runs when a Claude Code session ends. Collects session metrics, persists
# a structured session file for continuity, signals learning extraction,
# posts to claude-mem if available, and warns about uncommitted changes.
#
# Cross-platform: macOS + Linux. Bash only, no exotic dependencies.
# All output goes to stderr. Always exits 0 (hooks must never block).
#
# Environment variables consumed:
#   CLAUDE_SESSION_ID       — Unique session identifier (optional)
#   CLAUDE_TRANSCRIPT_PATH  — Path to JSON transcript file (optional)
#   PROJECT_DIR             — Override for project root (optional)
#
# ============================================================================

# NOTE: No set -euo pipefail — hooks must ALWAYS exit 0.
# Errors handled explicitly at each call site.

# Profile gate — exit if not enabled for current HOOK_PROFILE
source "$(dirname "$0")/run-with-flags.sh" "session-end" || exit 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# All logging goes to stderr to avoid interfering with hook plumbing
log()  { echo "[SessionEnd] $*" >&2; }
warn() { echo "[SessionEnd] WARNING: $*" >&2; }

# Portable date: macOS date vs GNU date
# Usage: portable_date "+%Y-%m-%d" [optional: -r <epoch>]
portable_date() {
    date "$@" 2>/dev/null || true
}

# Safe grep -c that never fails (returns 0 on no match / missing file)
count_grep() {
    grep -c "$1" "$2" 2>/dev/null || echo 0
}

# ---------------------------------------------------------------------------
# Read stdin IMMEDIATELY (Stop hook may pass session data as JSON)
# Must happen before any other operation — stdin can only be read once.
# ---------------------------------------------------------------------------

STDIN_DATA=""
if [ ! -t 0 ]; then
    STDIN_DATA="$(cat 2>/dev/null || true)"
fi

# ---------------------------------------------------------------------------
# Project root detection (works with worktrees)
# ---------------------------------------------------------------------------

PROJECT_ROOT="${PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$PROJECT_ROOT" 2>/dev/null || true

PROJECT_NAME="$(basename "$(pwd)")"

# ---------------------------------------------------------------------------
# Timestamps & identifiers
# ---------------------------------------------------------------------------

TODAY="$(date +%Y-%m-%d)"
CURRENT_TIME="$(date +%H:%M)"
CURRENT_EPOCH="$(date +%s)"

# Short ID: last 6 chars of session ID, or PID-based fallback
if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    SHORT_ID="${CLAUDE_SESSION_ID: -6}"
else
    SHORT_ID="$(printf '%05d' $$)"
fi

# ---------------------------------------------------------------------------
# Directory setup
# ---------------------------------------------------------------------------

SESSIONS_DIR=".claude/sessions"
LEARNED_DIR=".claude/learned-skills"
SIGNALS_DIR=".claude/signals"

mkdir -p "$SESSIONS_DIR" "$LEARNED_DIR" "$SIGNALS_DIR"

SESSION_FILE="$SESSIONS_DIR/${TODAY}-${SHORT_ID}-session.md"

# ---------------------------------------------------------------------------
# Idempotency check — skip if session file already written for this session
# ---------------------------------------------------------------------------

MARKER_FILE="$SESSIONS_DIR/.written-${SHORT_ID}"
if [ -f "$MARKER_FILE" ]; then
    log "Session file already written for ${SHORT_ID} — skipping (idempotent)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Git context
# ---------------------------------------------------------------------------

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

# Files modified in this session: uncommitted changes (staged + unstaged)
# plus any commits made today on this branch
FILES_MODIFIED=""
TESTS_MODIFIED=""
UNCOMMITTED_FILES=""

# Uncommitted changes (staged + unstaged + untracked)
UNCOMMITTED_FILES="$(git status --porcelain 2>/dev/null | awk '{print $2}' || true)"
HAS_UNCOMMITTED=false
if [ -n "$UNCOMMITTED_FILES" ]; then
    HAS_UNCOMMITTED=true
fi

# All files touched: uncommitted + committed today on this branch
# We combine git diff (uncommitted) with git log (today's commits)
FILES_FROM_UNCOMMITTED="$(git diff --name-only HEAD 2>/dev/null || true)"
FILES_FROM_STAGED="$(git diff --cached --name-only 2>/dev/null || true)"
FILES_FROM_COMMITS="$(git log --since="$TODAY" --name-only --pretty=format: 2>/dev/null | sort -u || true)"

# Merge and deduplicate
FILES_MODIFIED="$(printf '%s\n%s\n%s' \
    "$FILES_FROM_UNCOMMITTED" \
    "$FILES_FROM_STAGED" \
    "$FILES_FROM_COMMITS" \
    | grep -v '^$' | sort -u || true)"

# Filter test files (common patterns: *Test.java, *_test.go, *.test.ts, test_*.py, *Spec.*)
TESTS_MODIFIED="$(echo "$FILES_MODIFIED" \
    | grep -iE '(test[_.]|_test\.|\.test\.|\.spec\.|tests/|__tests__/)' \
    || true)"

# ---------------------------------------------------------------------------
# Transcript analysis (if available)
# ---------------------------------------------------------------------------

TRANSCRIPT_PATH="${CLAUDE_TRANSCRIPT_PATH:-}"
USER_MESSAGES=0
TOOL_CALLS=0
TOTAL_MESSAGES=0
SESSION_STARTED=""
QUALIFIES_FOR_LEARNING=false

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Count user messages (JSON lines format: look for "type":"user" or role":"user")
    USER_MESSAGES="$(grep -cE '"type":"user"|"role":"user"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)"

    # Count tool calls (look for tool_use blocks or "type":"tool_use")
    TOOL_CALLS="$(grep -cE '"type":"tool_use"|"type":"tool_result"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)"

    # Total message blocks (rough: count "type" occurrences as proxy)
    TOTAL_MESSAGES="$(grep -c '"type":' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)"

    # Try to get session start time from file modification time of transcript
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: stat -f %m gives epoch
        TRANSCRIPT_EPOCH="$(stat -f %m "$TRANSCRIPT_PATH" 2>/dev/null || echo "")"
    else
        # Linux: stat -c %Y gives epoch
        TRANSCRIPT_EPOCH="$(stat -c %Y "$TRANSCRIPT_PATH" 2>/dev/null || echo "")"
    fi

    # Estimate session start from transcript creation time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        TRANSCRIPT_BIRTH="$(stat -f %B "$TRANSCRIPT_PATH" 2>/dev/null || echo "")"
        if [ -n "$TRANSCRIPT_BIRTH" ] && [ "$TRANSCRIPT_BIRTH" -gt 0 ] 2>/dev/null; then
            SESSION_STARTED="$(date -r "$TRANSCRIPT_BIRTH" +%H:%M 2>/dev/null || echo "")"
        fi
    else
        # Linux: birth time via stat -c %W (may be 0 if unsupported)
        TRANSCRIPT_BIRTH="$(stat -c %W "$TRANSCRIPT_PATH" 2>/dev/null || echo "")"
        if [ -n "$TRANSCRIPT_BIRTH" ] && [ "$TRANSCRIPT_BIRTH" -gt 0 ] 2>/dev/null; then
            SESSION_STARTED="$(date -d "@$TRANSCRIPT_BIRTH" +%H:%M 2>/dev/null || echo "")"
        fi
    fi

    # Check if session qualifies for learning extraction (≥10 user messages)
    if [ "$USER_MESSAGES" -ge 10 ]; then
        QUALIFIES_FOR_LEARNING=true
    fi

    log "Transcript found: $USER_MESSAGES user messages, $TOOL_CALLS tool calls"
else
    log "No transcript available (file-only mode)"
fi

# Fallback: try to get start time from existing .tmp session file
if [ -z "$SESSION_STARTED" ]; then
    EXISTING_TMP="$(find "$SESSIONS_DIR" -name "${TODAY}-${SHORT_ID}-session.tmp" 2>/dev/null | head -1)"
    if [ -n "$EXISTING_TMP" ] && [ -f "$EXISTING_TMP" ]; then
        SESSION_STARTED="$(grep -o '\*\*Started:\*\* [^ ]*' "$EXISTING_TMP" 2>/dev/null | sed 's/\*\*Started:\*\* //' || echo "")"
    fi
fi

# Final fallback for start time
SESSION_STARTED="${SESSION_STARTED:-$CURRENT_TIME}"

# Duration: use user message count as proxy (most meaningful metric)
DURATION_LABEL="~${USER_MESSAGES} messages"
if [ "$USER_MESSAGES" -eq 0 ]; then
    DURATION_LABEL="~0 messages (no transcript)"
fi

# ---------------------------------------------------------------------------
# Git diff summary (meaningful change context even without transcript)
# ---------------------------------------------------------------------------

DIFF_STAT=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
    DIFF_STAT="$(git diff --stat HEAD 2>/dev/null | tail -1 || true)"
fi

# ---------------------------------------------------------------------------
# Parse stdin JSON for session metadata (read earlier at script start)
# ---------------------------------------------------------------------------

# Extract fields from stdin JSON (if available)
if [ -n "$STDIN_DATA" ] && command -v python3 &>/dev/null; then
    STDIN_SESSION_ID="$(echo "$STDIN_DATA" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', d.get('sessionId', '')))
except: pass
" 2>/dev/null || true)"
    STDIN_TRANSCRIPT="$(echo "$STDIN_DATA" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path', d.get('transcriptPath', '')))
except: pass
" 2>/dev/null || true)"

    # Use stdin values as fallback if env vars are empty
    if [ -z "${CLAUDE_SESSION_ID:-}" ] && [ -n "$STDIN_SESSION_ID" ]; then
        export CLAUDE_SESSION_ID="$STDIN_SESSION_ID"
        SHORT_ID="${CLAUDE_SESSION_ID: -6}"
    fi
    if [ -z "$TRANSCRIPT_PATH" ] && [ -n "$STDIN_TRANSCRIPT" ] && [ -f "$STDIN_TRANSCRIPT" ]; then
        TRANSCRIPT_PATH="$STDIN_TRANSCRIPT"
        log "Transcript found via stdin: $TRANSCRIPT_PATH"
    fi
fi

# ---------------------------------------------------------------------------
# Build session summary text (for claude-mem and Notes)
# ---------------------------------------------------------------------------

FILE_COUNT="$(echo "$FILES_MODIFIED" | grep -c . 2>/dev/null || echo 0)"
TEST_COUNT="$(echo "$TESTS_MODIFIED" | grep -c . 2>/dev/null || echo 0)"

SUMMARY_TEXT="Session on ${TODAY} (${BRANCH}): ${USER_MESSAGES} user messages, ${TOOL_CALLS} tool calls, ${FILE_COUNT} files modified, ${TEST_COUNT} tests touched."
if [ -n "$DIFF_STAT" ]; then
    SUMMARY_TEXT="${SUMMARY_TEXT} Changes: ${DIFF_STAT}"
fi

# ---------------------------------------------------------------------------
# Write session file
# ---------------------------------------------------------------------------

{
    echo "# Session: ${TODAY}"
    echo ""
    echo "**Date:** ${TODAY}"
    echo "**Branch:** ${BRANCH}"
    echo "**Duration:** ${DURATION_LABEL}"
    echo "**Started:** ${SESSION_STARTED}"
    echo "**Ended:** ${CURRENT_TIME}"
    echo "**User Messages:** ${USER_MESSAGES}"
    echo "**Tool Calls:** ${TOOL_CALLS}"
    echo ""

    # Files Modified
    echo "## Files Modified"
    if [ -n "$FILES_MODIFIED" ]; then
        echo "$FILES_MODIFIED" | while IFS= read -r f; do
            [ -n "$f" ] && echo "- ${f}"
        done
    else
        echo "_No files modified._"
    fi
    echo ""

    # Tests Added/Modified
    echo "## Tests Added/Modified"
    if [ -n "$TESTS_MODIFIED" ]; then
        echo "$TESTS_MODIFIED" | while IFS= read -r f; do
            [ -n "$f" ] && echo "- ${f}"
        done
    else
        echo "_No test files changed._"
    fi
    echo ""

    # Summary
    echo "## Summary"
    echo "${SUMMARY_TEXT}"
    echo ""

    # Uncommitted Changes
    echo "## Uncommitted Changes"
    if [ "$HAS_UNCOMMITTED" = true ]; then
        echo "$UNCOMMITTED_FILES" | while IFS= read -r f; do
            [ -n "$f" ] && echo "- [ ] ${f}"
        done
    else
        echo "_All changes committed._"
    fi
    echo ""

    # Notes for Next Session
    echo "## Notes for Next Session"
    if [ "$QUALIFIES_FOR_LEARNING" = true ]; then
        echo "- Session qualified for learning extraction (${USER_MESSAGES} messages)"
    fi
    if [ "$HAS_UNCOMMITTED" = true ]; then
        echo "- Uncommitted changes detected — review before next session"
    fi
    if [ -n "$TESTS_MODIFIED" ]; then
        echo "- Tests were modified — verify they pass before continuing"
    fi
    echo "- [Auto-populated from context]"

} > "$SESSION_FILE"

log "Session file saved: ${SESSION_FILE}"

# Write to structured memory (Phase 1)
# Write to structured memory (Phase 1)
WRITE_SESSION="$(dirname "$0")/../memory/write-session.sh"
[ -x "$WRITE_SESSION" ] || WRITE_SESSION="${CLAUDE_PLUGIN_ROOT:-}/scripts/memory/write-session.sh"
if [ -x "$WRITE_SESSION" ]; then
    bash "$WRITE_SESSION" \
        "${TODAY}-${SHORT_ID}" \
        "$BRANCH" \
        "$FILE_COUNT" \
        "$USER_MESSAGES" \
        "$TOOL_CALLS" \
        "$SUMMARY_TEXT" 2>/dev/null || true
    log "Structured session written to .claude/memory/"
fi

# Write idempotency marker
echo "$CURRENT_EPOCH" > "$MARKER_FILE"

# Invoke cost-tracker inline
COST_TRACKER="$(dirname "$0")/cost-tracker.sh"
if [ -x "$COST_TRACKER" ]; then
    bash "$COST_TRACKER" </dev/null 2>&1 || true
fi

# Clean up any .tmp session file from session-start hook
EXISTING_TMP="$(find "$SESSIONS_DIR" -name "${TODAY}-${SHORT_ID}-session.tmp" 2>/dev/null | head -1)"
if [ -n "$EXISTING_TMP" ] && [ -f "$EXISTING_TMP" ]; then
    rm -f "$EXISTING_TMP" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Learning extraction signal
# ---------------------------------------------------------------------------

if [ "$QUALIFIES_FOR_LEARNING" = true ]; then
    log "Session qualifies for learning extraction"

    # Write signal file for continuous-learning system to pick up
    SIGNAL_FILE="$SIGNALS_DIR/learning-${TODAY}-${SHORT_ID}.signal"
    {
        echo "session_id=${CLAUDE_SESSION_ID:-$$}"
        echo "date=${TODAY}"
        echo "branch=${BRANCH}"
        echo "user_messages=${USER_MESSAGES}"
        echo "tool_calls=${TOOL_CALLS}"
        echo "transcript=${TRANSCRIPT_PATH}"
        echo "session_file=${SESSION_FILE}"
        echo "timestamp=${CURRENT_EPOCH}"
    } > "$SIGNAL_FILE"

    log "Learning signal written: ${SIGNAL_FILE}"
else
    log "Session too short for learning extraction (${USER_MESSAGES} < 10 messages)"
fi

# ---------------------------------------------------------------------------
# claude-mem integration (graceful — never block on failure)
# ---------------------------------------------------------------------------

CLAUDE_MEM_PORT=37777
CLAUDE_MEM_URL="http://localhost:${CLAUDE_MEM_PORT}/api/sessions"

# Check if claude-mem is listening (timeout 2s)
if curl -sf --max-time 2 "http://localhost:${CLAUDE_MEM_PORT}/health" > /dev/null 2>&1 \
   || curl -sf --max-time 2 "$CLAUDE_MEM_URL" -o /dev/null 2>&1; then

    # Build JSON payload (manual — no jq dependency)
    # Escape special chars in strings for JSON safety
    json_escape() {
        if command -v python3 &>/dev/null; then
            python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])" "$1" 2>/dev/null || echo "$1"
        else
            local s="$1"
            s="${s//\\/\\\\}"
            s="${s//\"/\\\"}"
            printf '%s' "$s" | tr '\n' ' ' | tr '\t' ' '
        fi
    }

    JSON_FILES_LIST=""
    if [ -n "$FILES_MODIFIED" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            f_escaped="$(json_escape "$f")"
            if [ -n "$JSON_FILES_LIST" ]; then
                JSON_FILES_LIST="${JSON_FILES_LIST},\"${f_escaped}\""
            else
                JSON_FILES_LIST="\"${f_escaped}\""
            fi
        done <<< "$FILES_MODIFIED"
    fi

    PAYLOAD="$(cat <<JSONEOF
{
  "project": "$(json_escape "$PROJECT_NAME")",
  "branch": "$(json_escape "$BRANCH")",
  "date": "${TODAY}",
  "session_id": "$(json_escape "${CLAUDE_SESSION_ID:-$$}")",
  "user_messages": ${USER_MESSAGES},
  "tool_calls": ${TOOL_CALLS},
  "files_modified": [${JSON_FILES_LIST}],
  "session_file": "$(json_escape "$SESSION_FILE")",
  "summary": "$(json_escape "$SUMMARY_TEXT")"
}
JSONEOF
)"

    # POST to claude-mem (fire-and-forget, max 5s timeout)
    HTTP_CODE="$(curl -sf --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        -o /dev/null \
        -w "%{http_code}" \
        "$CLAUDE_MEM_URL" 2>/dev/null || echo "000")"

    if [[ "$HTTP_CODE" =~ ^[0-9]+$ ]] && [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ] 2>/dev/null; then
        log "Session saved to claude-mem (HTTP ${HTTP_CODE})"
    else
        log "claude-mem POST returned HTTP ${HTTP_CODE} (session file still saved locally)"
    fi
else
    log "claude-mem: not running (file-only mode)"
fi

# ---------------------------------------------------------------------------
# Checkpoint verification — warn about uncommitted changes
# ---------------------------------------------------------------------------

if [ "$HAS_UNCOMMITTED" = true ]; then
    UNCOMMITTED_COUNT="$(echo "$UNCOMMITTED_FILES" | grep -c . 2>/dev/null || echo 0)"
    warn "Uncommitted changes detected (${UNCOMMITTED_COUNT} files)"

    # Print first 20 files to stderr (avoid flooding on huge diffs)
    echo "$UNCOMMITTED_FILES" | head -20 | while IFS= read -r f; do
        [ -n "$f" ] && echo "  - $f" >&2
    done

    if [ "$UNCOMMITTED_COUNT" -gt 20 ]; then
        echo "  ... and $((UNCOMMITTED_COUNT - 20)) more" >&2
    fi
else
    log "All changes committed ✓"
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

log "Done. Branch=${BRANCH} Messages=${USER_MESSAGES} Files=${FILE_COUNT} Tests=${TEST_COUNT}"

# Hooks must always exit 0
exit 0
