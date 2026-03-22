#!/usr/bin/env bash
# Tiered context retrieval from structured memory
# Outputs context to stdout for session-start injection
# Token budget: Tier0 ~50, Tier1 ~200, Tier2 ~500
# NOTE: No set -euo pipefail — called from hooks that must never fail.

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMORY_DIR="$PROJECT_ROOT/.claude/memory"
INDEX_FILE="$MEMORY_DIR/sessions/index.json"
ACTIVE_WORK="$MEMORY_DIR/context/active-work.json"

# Exit silently if memory not initialized
[ -d "$MEMORY_DIR" ] || exit 0

# Require python3 for safe JSON parsing (pass paths via sys.argv, not inline)
command -v python3 &>/dev/null || exit 0

OUTPUT=""

# --- Tier 0: Session index (~50 tokens) ---
if [ -f "$INDEX_FILE" ]; then
  TIER0="$(python3 - "$INDEX_FILE" <<'PYEOF'
import json, sys
try:
    idx = json.load(open(sys.argv[1]))
    # Deduplicate by ID, keep latest
    seen = set()
    sessions = []
    for s in idx.get("sessions", []):
        sid = s.get("id", "")
        if sid not in seen:
            seen.add(sid)
            sessions.append(s)
        if len(sessions) >= 5:
            break
    if sessions:
        print("Recent sessions:")
        for s in sessions:
            print(f"  - {s.get('date','?')[:10]} [{s.get('branch','?')}] {s.get('summary','')[:80]}")
except Exception:
    pass
PYEOF
  )" 2>/dev/null || true
  [ -n "$TIER0" ] && OUTPUT="$TIER0"
fi

# --- Tier 1: Active work context (~200 tokens) ---
if [ -f "$ACTIVE_WORK" ]; then
  TIER1="$(python3 - "$ACTIVE_WORK" <<'PYEOF'
import json, sys
try:
    work = json.load(open(sys.argv[1]))
    task = work.get("current_task", "")
    if task:
        print(f"Active task: {task}")
        for note in work.get("notes", [])[:5]:
            print(f"  - {note}")
except Exception:
    pass
PYEOF
  )" 2>/dev/null || true
  [ -n "$TIER1" ] && OUTPUT="${OUTPUT:+$OUTPUT
}$TIER1"
fi

# --- Tier 2: Latest session detail (~500 tokens) ---
if [ -f "$INDEX_FILE" ]; then
  LATEST_ID="$(python3 - "$INDEX_FILE" <<'PYEOF'
import json, sys
try:
    idx = json.load(open(sys.argv[1]))
    ss = idx.get("sessions", [])
    if ss:
        print(ss[0].get("id", ""))
except Exception:
    pass
PYEOF
  )" 2>/dev/null || true

  if [ -n "$LATEST_ID" ]; then
    LATEST_FILE="$MEMORY_DIR/sessions/${LATEST_ID}.json"
    if [ -f "$LATEST_FILE" ]; then
      TIER2="$(python3 - "$LATEST_FILE" <<'PYEOF'
import json, sys
try:
    s = json.load(open(sys.argv[1]))
    print(f"Last session: {s.get('summary','N/A')}")
    print(f"  Branch: {s.get('branch','?')}, Files: {s.get('files_modified',0)}, Messages: {s.get('user_messages',0)}")
except Exception:
    pass
PYEOF
      )" 2>/dev/null || true
      [ -n "$TIER2" ] && OUTPUT="${OUTPUT:+$OUTPUT
}$TIER2"
    fi
  fi
fi

# Output accumulated context
if [ -n "$OUTPUT" ]; then
  echo "$OUTPUT"
fi
