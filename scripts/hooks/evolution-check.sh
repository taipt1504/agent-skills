#!/usr/bin/env bash
# evolution-check.sh — Stop hook for pattern → Claude native auto-memory promotion (v4.1)
#
# v4.1 change: no longer scans third-party instincts.jsonl. Instead:
# - Reads .claude/memory/shared/pattern-observations.jsonl (plugin-managed)
# - When threshold met, suggests via stderr: "Consider asking Claude to remember: <pattern>"
# - User invokes /meta evolve OR types "remember <pattern>" — Claude writes to native MEMORY.md
#
# Thresholds (configurable via devco-config.json memory.promotion.*):
#   - confidence ≥ 0.8
#   - occurrences ≥ 3
#   - distinct sessions ≥ 2
#   - distinct projects ≥ 2
set -euo pipefail

source "$(dirname "$0")/run-with-flags.sh" "evolution-check" || exit 0

WORKSPACE="${CLAUDE_PROJECT_DIR:-$(/usr/bin/git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
OBSERVATIONS="$WORKSPACE/.claude/memory/shared/pattern-observations.jsonl"
OUTPUT="$WORKSPACE/.claude/memory/shared/promotion-candidates.md"

/bin/mkdir -p "$(dirname "$OUTPUT")"

# Skip if no observations file
if [ ! -f "$OBSERVATIONS" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[evolution-check] python3 not found — skip" >&2
  exit 0
fi

python3 - "$OBSERVATIONS" "$OUTPUT" <<'PY' >&2 || true
import json
import sys
from collections import defaultdict
from pathlib import Path

OBS_PATH, OUT_PATH = sys.argv[1], sys.argv[2]

THRESHOLD_CONFIDENCE = 0.8
THRESHOLD_OCCURRENCES = 3
THRESHOLD_SESSIONS = 2
THRESHOLD_PROJECTS = 2

candidates = defaultdict(lambda: {
    "pattern": "",
    "confidences": [],
    "occurrences": 0,
    "sessions": set(),
    "projects": set(),
    "last_seen": "",
    "examples": [],
})

obs_path = Path(OBS_PATH)
try:
    for line in obs_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        pid = entry.get("pattern_id") or entry.get("pattern", "")[:80]
        if not pid:
            continue
        c = candidates[pid]
        c["pattern"] = entry.get("pattern", pid)
        c["confidences"].append(float(entry.get("confidence", 0.5)))
        c["occurrences"] += 1
        if entry.get("session_id"):
            c["sessions"].add(entry["session_id"])
        if entry.get("project"):
            c["projects"].add(entry["project"])
        c["last_seen"] = max(c["last_seen"], entry.get("timestamp", ""))
        if len(c["examples"]) < 3 and entry.get("context"):
            c["examples"].append(entry["context"])
except OSError:
    sys.exit(0)

qualifying = []
for pid, c in candidates.items():
    avg_conf = sum(c["confidences"]) / len(c["confidences"]) if c["confidences"] else 0
    if (avg_conf >= THRESHOLD_CONFIDENCE
            and c["occurrences"] >= THRESHOLD_OCCURRENCES
            and len(c["sessions"]) >= THRESHOLD_SESSIONS
            and len(c["projects"]) >= THRESHOLD_PROJECTS):
        qualifying.append((pid, c, avg_conf))

if not qualifying:
    Path(OUT_PATH).write_text("# Promotion candidates\n\n_(none meet thresholds yet)_\n")
    print("[evolution-check] 0 candidates")
    sys.exit(0)

lines = [
    "# Promotion candidates",
    "",
    f"_{len(qualifying)} pattern(s) meet thresholds — ready for promotion to Claude's native auto-memory_",
    "",
    "**Thresholds:** confidence ≥ 0.8, occurrences ≥ 3, sessions ≥ 2, projects ≥ 2",
    "",
    "**To promote:** type one of:",
    "1. `/meta evolve` — walk through candidates, decide each",
    "2. `remember: <pattern>` — Claude writes to ~/.claude/projects/<project>/memory/MEMORY.md directly",
    "3. Use `/memory` command to view/edit native auto-memory",
    "",
]

for pid, c, avg_conf in sorted(qualifying, key=lambda x: -x[2]):
    lines += [
        f"## {c['pattern'][:100]}",
        "",
        f"- **ID:** `{pid}`",
        f"- **Confidence:** {avg_conf:.2f} (avg of {len(c['confidences'])})",
        f"- **Occurrences:** {c['occurrences']}",
        f"- **Sessions:** {len(c['sessions'])} distinct",
        f"- **Projects:** {len(c['projects'])} distinct",
        f"- **Last seen:** {c['last_seen'] or 'unknown'}",
        "",
        "### Example occurrences",
    ]
    for i, ex in enumerate(c["examples"], 1):
        lines.append(f"{i}. {str(ex)[:200]}")
    lines.append("")

Path(OUT_PATH).write_text("\n".join(lines))
print(f"[evolution-check] {len(qualifying)} candidate(s) → {OUT_PATH}")
print(f"[evolution-check] Run /meta evolve to review, or type 'remember: <pattern>' for Claude auto-memory")
PY

exit 0
