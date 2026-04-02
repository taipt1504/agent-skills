#!/usr/bin/env bash
# build-checkpoint.sh — Checkpoint-Resume for BUILD phase
# Fires on PostToolUse for Edit/Write/MultiEdit operations
# Persists state to enable recovery after context reset

trap 'exit 0' ERR

source "$(dirname "$0")/run-with-flags.sh" "build-checkpoint" || exit 0

# Extract file path from stdin (tool input)
read -r TOOL_INPUT
FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Handle various tool input formats: direct path or nested structure
    if isinstance(data, dict) and 'file_path' in data:
        print(data['file_path'])
    elif isinstance(data, str):
        print(data)
    else:
        print('')
except:
    print('')
" <<< "$TOOL_INPUT")

[ -z "$FILE_PATH" ] && exit 0

# Check workflow phase
WORKFLOW_STATE=".claude/workflow-state.json"
if [ ! -f "$WORKFLOW_STATE" ]; then
    exit 0
fi

PHASE=$(python3 -c "
import json
try:
    with open('$WORKFLOW_STATE') as f:
        print(json.load(f).get('phase', ''))
except:
    print('')
")

[ "$PHASE" != "BUILD" ] && exit 0

# Ensure checkpoint directory
mkdir -p .claude/sessions

CHECKPOINT_FILE=".claude/sessions/build-checkpoint.json"
SPEC_REF=$(python3 -c "
import json
try:
    with open('$WORKFLOW_STATE') as f:
        print(json.load(f).get('specRef', ''))
except:
    print('')
")

# Update checkpoint (append-only pattern)
python3 << 'PYTHON_EOF'
import json
from datetime import datetime
from pathlib import Path
import os

checkpoint_path = Path(".claude/sessions/build-checkpoint.json")
file_path = os.getenv("FILE_PATH", "").strip()
spec_ref = os.getenv("SPEC_REF", "").strip()

if not file_path:
    exit(0)

# Read existing checkpoint or initialize
if checkpoint_path.exists():
    try:
        with open(checkpoint_path) as f:
            checkpoint = json.load(f)
    except:
        checkpoint = {}
else:
    checkpoint = {
        "active": True,
        "phase": "BUILD",
        "startedAt": datetime.utcnow().isoformat() + "Z",
        "sessionId": os.getenv("SESSION_ID", "default")
    }

# Add/update fields
checkpoint["phase"] = "BUILD"
checkpoint["active"] = True
checkpoint["lastModifiedAt"] = datetime.utcnow().isoformat() + "Z"

if spec_ref:
    checkpoint["specRef"] = spec_ref

# Dedup file in modifiedFiles array
if "modifiedFiles" not in checkpoint:
    checkpoint["modifiedFiles"] = []

if file_path not in checkpoint["modifiedFiles"]:
    checkpoint["modifiedFiles"].append(file_path)

checkpoint["fileCount"] = len(checkpoint["modifiedFiles"])

# Write atomically
with open(checkpoint_path, "w") as f:
    json.dump(checkpoint, f, indent=2)
PYTHON_EOF

exit 0
