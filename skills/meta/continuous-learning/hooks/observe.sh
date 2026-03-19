#!/bin/bash
# Continuous Learning v2 - Observation Hook
#
# Captures tool use events for pattern analysis.
# Claude Code passes hook data via stdin as JSON.
#
# Features:
#   - Local JSONL logging (original behavior)
#   - Optional claude-mem integration (fire-and-forget POST)
#
# Hook config (in ~/.claude/settings.json):
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "*",
#       "hooks": [{ "type": "command", "command": "~/.claude/skills/continuous-learning/hooks/observe.sh" }]
#     }],
#     "PostToolUse": [{
#       "matcher": "*",
#       "hooks": [{ "type": "command", "command": "~/.claude/skills/continuous-learning/hooks/observe.sh" }]
#     }]
#   }
# }

set -e

CONFIG_DIR="${HOME}/.claude/homunculus"
OBSERVATIONS_FILE="${CONFIG_DIR}/observations.jsonl"
MAX_FILE_SIZE_MB=10

# Skill config (for claude-mem settings)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_CONFIG="${SCRIPT_DIR}/../config.json"

# Ensure directory exists
mkdir -p "$CONFIG_DIR"

# Skip if disabled
if [ -f "$CONFIG_DIR/disabled" ]; then
  exit 0
fi

# Read JSON from stdin (Claude Code hook format)
INPUT_JSON=$(cat)

# Exit if no input
if [ -z "$INPUT_JSON" ]; then
  exit 0
fi

# Parse using python (more reliable than jq for complex JSON)
PARSED=$(python3 << EOF
import json
import sys

try:
    data = json.loads('''$INPUT_JSON''')

    # Extract fields - Claude Code hook format
    hook_type = data.get('hook_type', 'unknown')  # PreToolUse or PostToolUse
    tool_name = data.get('tool_name', data.get('tool', 'unknown'))
    tool_input = data.get('tool_input', data.get('input', {}))
    tool_output = data.get('tool_output', data.get('output', ''))
    session_id = data.get('session_id', 'unknown')

    # Truncate large inputs/outputs
    if isinstance(tool_input, dict):
        tool_input_str = json.dumps(tool_input)[:5000]
    else:
        tool_input_str = str(tool_input)[:5000]

    if isinstance(tool_output, dict):
        tool_output_str = json.dumps(tool_output)[:5000]
    else:
        tool_output_str = str(tool_output)[:5000]

    # Determine event type
    event = 'tool_start' if 'Pre' in hook_type else 'tool_complete'

    print(json.dumps({
        'parsed': True,
        'event': event,
        'tool': tool_name,
        'input': tool_input_str if event == 'tool_start' else None,
        'output': tool_output_str if event == 'tool_complete' else None,
        'session': session_id
    }))
except Exception as e:
    print(json.dumps({'parsed': False, 'error': str(e)}))
EOF
)

# Check if parsing succeeded
PARSED_OK=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('parsed', False))")

if [ "$PARSED_OK" != "True" ]; then
  # Fallback: log raw input for debugging
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "{\"timestamp\":\"$timestamp\",\"event\":\"parse_error\",\"raw\":$(echo "$INPUT_JSON" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:1000]))')}" >> "$OBSERVATIONS_FILE"
  exit 0
fi

# Archive if file too large
if [ -f "$OBSERVATIONS_FILE" ]; then
  file_size_mb=$(du -m "$OBSERVATIONS_FILE" 2>/dev/null | cut -f1)
  if [ "${file_size_mb:-0}" -ge "$MAX_FILE_SIZE_MB" ]; then
    archive_dir="${CONFIG_DIR}/observations.archive"
    mkdir -p "$archive_dir"
    mv "$OBSERVATIONS_FILE" "$archive_dir/observations-$(date +%Y%m%d-%H%M%S).jsonl"
  fi
fi

# Build and write observation to local JSONL
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 << EOF
import json

parsed = json.loads('''$PARSED''')
observation = {
    'timestamp': '$timestamp',
    'event': parsed['event'],
    'tool': parsed['tool'],
    'session': parsed['session']
}

if parsed['input']:
    observation['input'] = parsed['input']
if parsed['output']:
    observation['output'] = parsed['output']

with open('$OBSERVATIONS_FILE', 'a') as f:
    f.write(json.dumps(observation) + '\n')
EOF

# Signal observer if running
OBSERVER_PID_FILE="${CONFIG_DIR}/.observer.pid"
if [ -f "$OBSERVER_PID_FILE" ]; then
  observer_pid=$(cat "$OBSERVER_PID_FILE")
  if kill -0 "$observer_pid" 2>/dev/null; then
    kill -USR1 "$observer_pid" 2>/dev/null || true
  fi
fi

# ── claude-mem integration (fire-and-forget) ──────────────────────────
# Send observation to claude-mem if enabled and reachable.
# This block is fully optional — failure here never affects the hook.

_send_to_claude_mem() {
  # Need curl
  command -v curl >/dev/null 2>&1 || return 0

  # Need config file
  [ -f "$SKILL_CONFIG" ] || return 0

  # Parse claude-mem config + build payload in one python call
  local payload
  payload=$(python3 << EOF
import json, os

# Read skill config
try:
    with open('$SKILL_CONFIG') as f:
        cfg = json.load(f).get('claude_mem', {})
except:
    cfg = {}

# Check enabled
if not cfg.get('enabled', False):
    exit(1)

# Check send_observations flag
if not cfg.get('send_observations', True):
    exit(1)

host = cfg.get('host', 'localhost')
port = cfg.get('port', 37777)
timeout = cfg.get('timeout_seconds', 2)

# Build payload from parsed observation
parsed = json.loads('''$PARSED''')
project = os.path.basename(os.getcwd())

obs = {
    'type': 'tool_use',
    'tool': parsed['tool'],
    'event': parsed['event'],
    'input': (parsed.get('input') or '')[:2000],
    'output': (parsed.get('output') or '')[:2000],
    'session': parsed['session'],
    'project': project,
    'timestamp': '$timestamp'
}

# Print config line then payload line
print(json.dumps({'host': host, 'port': port, 'timeout': timeout}))
print(json.dumps(obs))
EOF
  ) || return 0

  # Extract config and payload (two lines from python)
  local cm_config cm_payload cm_host cm_port cm_timeout
  cm_config=$(echo "$payload" | head -1)
  cm_payload=$(echo "$payload" | tail -1)

  cm_host=$(echo "$cm_config" | python3 -c "import json,sys; print(json.load(sys.stdin)['host'])")
  cm_port=$(echo "$cm_config" | python3 -c "import json,sys; print(json.load(sys.stdin)['port'])")
  cm_timeout=$(echo "$cm_config" | python3 -c "import json,sys; print(json.load(sys.stdin)['timeout'])")

  local cm_url="http://${cm_host}:${cm_port}/api/observations"

  # Fire-and-forget: background curl, discard all output, ignore errors
  curl -s -o /dev/null --max-time "${cm_timeout}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$cm_payload" \
    "$cm_url" &

  echo "[observe] Sent observation to claude-mem (${cm_host}:${cm_port})" >&2
}

# Run claude-mem send — never let it fail the hook
_send_to_claude_mem >/dev/null 2>&1 || true

exit 0
