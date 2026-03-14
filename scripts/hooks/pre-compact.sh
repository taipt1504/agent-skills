#!/usr/bin/env bash
#
# PreCompact Hook - Save state before context compaction
# Cross-platform (macOS, Linux)
#
# Runs before Claude compacts context, giving you a chance to
# preserve important state that might get lost in summarization.
#
# Features:
#   - Local compaction logging (original behavior)
#   - Active files snapshot for post-compact recovery
#   - Optional claude-mem integration (fire-and-forget POST)
#

# Profile gate
source "$(dirname "$0")/run-with-flags.sh" "pre-compact" || exit 0

# All output to stderr
exec 1>&2

# Never fail the hook
trap 'exit 0' ERR

# Resolve project root (works in worktrees too)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

PROJECT_NAME="$(basename "$PROJECT_ROOT")"

# Get directories and timestamps (relative to project root)
SESSIONS_DIR=".claude/sessions"
COMPACTION_LOG="$SESSIONS_DIR/compaction-log.txt"

# Cross-platform timestamp (macOS date vs GNU date)
if date --version >/dev/null 2>&1; then
  # GNU/Linux
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
else
  # macOS/BSD
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi
TIME_STR=$(date "+%H:%M")

# Ensure directory exists
mkdir -p "$SESSIONS_DIR"

# ── 1. Log compaction event (original behavior) ──────────────────────
echo "[$TIMESTAMP] Context compaction triggered" >> "$COMPACTION_LOG"

# ── 2. Find active session ───────────────────────────────────────────
ACTIVE_SESSION=$(find "$SESSIONS_DIR" -name "*.tmp" -type f 2>/dev/null | sort -r | head -1)
SESSION_ID="unknown"

if [ -n "$ACTIVE_SESSION" ] && [ -f "$ACTIVE_SESSION" ]; then
  SESSION_ID="$(basename "$ACTIVE_SESSION" .tmp)"

  # Write compaction marker to session file
  {
    echo ""
    echo "---"
    echo "**[Compaction occurred at $TIME_STR]** - Context was summarized"
  } >> "$ACTIVE_SESSION"
fi

# ── 3. Collect active files (from git diff) ──────────────────────────
ACTIVE_FILES_JSON="[]"
ACTIVE_FILES_COUNT=0

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Get modified + staged + untracked files
  ACTIVE_FILES_JSON=$(python3 -c "
import subprocess, json

files = set()

# Staged files
try:
    out = subprocess.check_output(['git', 'diff', '--cached', '--name-only'], text=True, stderr=subprocess.DEVNULL)
    files.update(f.strip() for f in out.splitlines() if f.strip())
except:
    pass

# Modified (unstaged) files
try:
    out = subprocess.check_output(['git', 'diff', '--name-only'], text=True, stderr=subprocess.DEVNULL)
    files.update(f.strip() for f in out.splitlines() if f.strip())
except:
    pass

# Recently modified tracked files (last 30 mins)
try:
    import os, time
    now = time.time()
    out = subprocess.check_output(['git', 'ls-files', '-m'], text=True, stderr=subprocess.DEVNULL)
    for f in out.splitlines():
        f = f.strip()
        if f and os.path.exists(f):
            mtime = os.path.getmtime(f)
            if now - mtime < 1800:  # 30 minutes
                files.add(f)
except:
    pass

print(json.dumps(sorted(list(files))[:100]))
" 2>/dev/null) || ACTIVE_FILES_JSON="[]"

  ACTIVE_FILES_COUNT=$(echo "$ACTIVE_FILES_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null) || ACTIVE_FILES_COUNT=0
fi

# Save active files list to session recovery file
RECOVERY_FILE="$SESSIONS_DIR/pre-compact-${SESSION_ID}.json"
python3 -c "
import json
recovery = {
    'timestamp': '$ISO_TIMESTAMP',
    'session': '$SESSION_ID',
    'project': '$PROJECT_NAME',
    'active_files': json.loads('''$ACTIVE_FILES_JSON'''),
    'compaction_marker': True
}
with open('$RECOVERY_FILE', 'w') as f:
    json.dump(recovery, f, indent=2)
    f.write('\n')
" 2>/dev/null || true

# ── 4. Collect active instincts ──────────────────────────────────────
INSTINCTS_DIR="${HOME}/.claude/homunculus/instincts/personal"
ACTIVE_INSTINCTS_JSON="[]"
ACTIVE_INSTINCTS_COUNT=0

if [ -d "$INSTINCTS_DIR" ]; then
  ACTIVE_INSTINCTS_JSON=$(python3 -c "
import json, os, glob

instinct_dir = '$INSTINCTS_DIR'
high_conf = []

for fp in glob.glob(os.path.join(instinct_dir, '*.json')):
    try:
        with open(fp) as f:
            inst = json.load(f)
        conf = inst.get('confidence', 0)
        if conf >= 0.5:
            high_conf.append({
                'id': inst.get('id', os.path.basename(fp)),
                'description': inst.get('description', '')[:200],
                'confidence': conf
            })
    except:
        continue

# Sort by confidence descending, take top 20
high_conf.sort(key=lambda x: x['confidence'], reverse=True)
print(json.dumps(high_conf[:20]))
" 2>/dev/null) || ACTIVE_INSTINCTS_JSON="[]"

  ACTIVE_INSTINCTS_COUNT=$(echo "$ACTIVE_INSTINCTS_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null) || ACTIVE_INSTINCTS_COUNT=0
fi

# ── 5. claude-mem integration (fire-and-forget) ──────────────────────
# Send compaction snapshot to claude-mem if enabled and reachable.

_send_to_claude_mem() {
  command -v curl >/dev/null 2>&1 || return 0

  # Find skill config — check a few known locations
  local skill_config=""
  for candidate in \
    "${HOME}/.claude/skills/continuous-learning-v2/config.json" \
    "${HOME}/.claude/homunculus/config.json" \
    "${PROJECT_ROOT}/.claude/skills/continuous-learning-v2/config.json"; do
    if [ -f "$candidate" ]; then
      skill_config="$candidate"
      break
    fi
  done

  # Also check the installed skills repo location
  if [ -z "$skill_config" ]; then
    # Try to find via the observe.sh sibling
    local obs_dir
    obs_dir="$(dirname "$(command -v observe.sh 2>/dev/null || echo "")" 2>/dev/null)"
    if [ -n "$obs_dir" ] && [ -f "$obs_dir/../config.json" ]; then
      skill_config="$obs_dir/../config.json"
    fi
  fi

  [ -n "$skill_config" ] && [ -f "$skill_config" ] || return 0

  # Parse config and build payload
  local payload_output
  payload_output=$(python3 -c "
import json

# Read config
with open('$skill_config') as f:
    cfg = json.load(f).get('claude_mem', {})

if not cfg.get('enabled', False):
    exit(1)
if not cfg.get('send_compaction_events', True):
    exit(1)

host = cfg.get('host', 'localhost')
port = cfg.get('port', 37777)
timeout = cfg.get('timeout_seconds', 2)

# Determine compaction reason heuristic
reason = 'auto'
# Could be enhanced: check if user-requested via env var, etc.

active_files = json.loads('''$ACTIVE_FILES_JSON''')
active_instincts = json.loads('''$ACTIVE_INSTINCTS_JSON''')

payload = {
    'project': '$PROJECT_NAME',
    'session': '$SESSION_ID',
    'active_files': active_files,
    'active_instincts': active_instincts,
    'compaction_reason': reason
}

# Print config line then payload line
print(json.dumps({'host': host, 'port': port, 'timeout': timeout}))
print(json.dumps(payload))
" 2>/dev/null) || return 0

  local cm_config cm_payload cm_host cm_port cm_timeout
  cm_config=$(echo "$payload_output" | head -1)
  cm_payload=$(echo "$payload_output" | tail -1)

  cm_host=$(echo "$cm_config" | python3 -c "import json,sys; print(json.load(sys.stdin)['host'])" 2>/dev/null) || return 0
  cm_port=$(echo "$cm_config" | python3 -c "import json,sys; print(json.load(sys.stdin)['port'])" 2>/dev/null) || return 0
  cm_timeout=$(echo "$cm_config" | python3 -c "import json,sys; print(json.load(sys.stdin)['timeout'])" 2>/dev/null) || return 0

  local cm_url="http://${cm_host}:${cm_port}/api/sessions/compact"

  # Fire-and-forget: background curl
  curl -s -o /dev/null --max-time "${cm_timeout}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$cm_payload" \
    "$cm_url" &

  echo "[PreCompact] Sent compaction snapshot to claude-mem (${cm_host}:${cm_port})"
}

# Run claude-mem send — never let it fail the hook
_send_to_claude_mem 2>/dev/null || true

# ── 6. Print summary ─────────────────────────────────────────────────
echo "[PreCompact] Saved ${ACTIVE_FILES_COUNT} active files, ${ACTIVE_INSTINCTS_COUNT} instincts to claude-mem"
echo "[PreCompact] Recovery file: ${RECOVERY_FILE}"

exit 0
