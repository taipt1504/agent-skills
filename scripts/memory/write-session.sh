#!/usr/bin/env bash
# Write a structured session to .claude/memory/sessions/
# Usage: write-session.sh <session_id> <branch> <files_modified_count> <user_messages> <tool_calls> <summary_text>
# NOTE: No set -euo pipefail — called from hooks that must never fail.

SESSION_ID="${1:?session_id required}"
BRANCH="${2:-unknown}"
FILES_COUNT="${3:-0}"
USER_MESSAGES="${4:-0}"
TOOL_CALLS="${5:-0}"
SUMMARY="${6:-No summary}"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMORY_DIR="$PROJECT_ROOT/.claude/memory"
SESSIONS_DIR="$MEMORY_DIR/sessions"
INDEX_FILE="$SESSIONS_DIR/index.json"

# Ensure directories exist
mkdir -p "$SESSIONS_DIR"
[ -f "$INDEX_FILE" ] || echo '{"sessions":[]}' > "$INDEX_FILE"

DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Write full session JSON via python3 (safe escaping) or fallback
SESSION_FILE="$SESSIONS_DIR/${SESSION_ID}.json"

if command -v python3 &>/dev/null; then
  # Use python3 for safe JSON generation — no shell escaping issues
  python3 - "$SESSION_FILE" "$INDEX_FILE" "$SESSION_ID" "$BRANCH" "$SUMMARY" "$FILES_COUNT" "$USER_MESSAGES" "$TOOL_CALLS" "$DATE" <<'PYEOF'
import json, sys

session_file = sys.argv[1]
index_file = sys.argv[2]
session_id = sys.argv[3]
branch = sys.argv[4]
summary = sys.argv[5]
files_count = int(sys.argv[6])
user_messages = int(sys.argv[7])
tool_calls = int(sys.argv[8])
date = sys.argv[9]

entry = {
    "id": session_id,
    "date": date,
    "branch": branch,
    "summary": summary,
    "files_modified": files_count,
    "user_messages": user_messages,
    "tool_calls": tool_calls
}

# Write full session JSON
with open(session_file, 'w') as f:
    json.dump(entry, f, indent=2)

# Update index: prepend, cap at 50
try:
    with open(index_file) as f:
        idx = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    idx = {"sessions": []}

index_entry = {"id": session_id, "date": date, "branch": branch, "summary": summary, "files_modified": files_count}
idx["sessions"].insert(0, index_entry)
idx["sessions"] = idx["sessions"][:5]  # Retain last 5, matching auto-prune policy

with open(index_file, 'w') as f:
    json.dump(idx, f, indent=2)
PYEOF

else
  # Fallback: write minimal JSON without shell escaping risks
  # Only safe for simple ASCII strings
  cat > "$SESSION_FILE" <<EOF
{"id":"$SESSION_ID","date":"$DATE","branch":"$BRANCH","summary":"session","files_modified":$FILES_COUNT,"user_messages":$USER_MESSAGES,"tool_calls":$TOOL_CALLS}
EOF
  echo "{\"sessions\":[{\"id\":\"$SESSION_ID\",\"date\":\"$DATE\",\"branch\":\"$BRANCH\",\"summary\":\"session\",\"files_modified\":$FILES_COUNT}]}" > "$INDEX_FILE"
fi

echo "$SESSION_FILE"
