#!/usr/bin/env bash
# =============================================================================
# session-save.sh — Session End Hook (v3.1)
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

# --- Update active work context ---
ACTIVE_WORK_FILE="$PROJECT_ROOT/.claude/memory/context/active-work.json"
if [ -d "$PROJECT_ROOT/.claude/memory/context" ]; then
  RECENT_COMMIT="$(git log -1 --oneline 2>/dev/null || echo "none")"
  cat > "$ACTIVE_WORK_FILE" <<EOF
{"current_task":"$BRANCH","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","notes":["Last commit: $RECENT_COMMIT"]}
EOF
fi

# Warn about uncommitted changes
if [ "$HAS_UNCOMMITTED" = true ]; then
  UNCOMMITTED_COUNT="$(echo "$UNCOMMITTED_FILES" | grep -c . 2>/dev/null || echo 0)"
  warn "Uncommitted changes: ${UNCOMMITTED_COUNT} files"
fi

log "Done. Branch=${BRANCH}"
exit 0
