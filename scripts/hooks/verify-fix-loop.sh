#!/usr/bin/env bash
# =============================================================================
# verify-fix-loop.sh — Ralph Verify/Fix Loop Pattern (v1.0)
# =============================================================================
# After Bash tool use: detect gradle test/build failures and emit recovery context.
# Fires on: PostToolUse (Bash command matching gradle test/build patterns)
#
# Pattern:
# 1. Detect gradle test/build failure (exit code != 0)
# 2. Extract normalized error signature (strip paths, line numbers, timestamps)
# 3. Read/update .claude/verify-fix-state.json loop state
# 4. Check circuit breakers: same error >= noProgressThreshold → ESCALATE
# 5. If under thresholds: emit additionalContext with /build-fix instruction
# =============================================================================

trap 'exit 0' ERR

source "$(dirname "$0")/run-with-flags.sh" "verify-fix-loop" || exit 0

DATA=$(cat)

# Extract bash command and exit code from tool input
BASH_CMD=$(echo "$DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('input','').get('command',''))" 2>/dev/null || echo "")
EXIT_CODE=$(echo "$DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('exitCode',0))" 2>/dev/null || echo "0")
TOOL_OUTPUT=$(echo "$DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('output',''))" 2>/dev/null || echo "")

# Check if this is a gradle test/build command
if ! echo "$BASH_CMD" | grep -qE '(gradle|gradlew).*(test|build|compile|check)'; then
  echo "$DATA"
  exit 0
fi

# If command succeeded, reset state and pass through
if [ "$EXIT_CODE" = "0" ]; then
  STATE_FILE=".claude/verify-fix-state.json"
  if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
  fi
  echo "$DATA"
  exit 0
fi

# --- Build failure detected (exit code != 0) ---

# Read config defaults
DEVCO_CONFIG=".claude/devco-config.json"
MAX_RETRY=3
NO_PROGRESS_THRESHOLD=3

if [ -f "$DEVCO_CONFIG" ]; then
  MAX_RETRY=$(python3 -c "import json; print(json.load(open('$DEVCO_CONFIG')).get('workflow',{}).get('maxRetryOnFail',3))" 2>/dev/null || echo 3)
  NO_PROGRESS_THRESHOLD=$(python3 -c "import json; print(json.load(open('$DEVCO_CONFIG')).get('workflow',{}).get('noProgressThreshold',3))" 2>/dev/null || echo 3)
fi

# Normalize error: extract first error line and remove line numbers/paths/timestamps
ERROR_SAMPLE=$(echo "$TOOL_OUTPUT" | grep -iE 'error:|exception:|failed|FAILURE' | head -1)
if [ -z "$ERROR_SAMPLE" ]; then
  ERROR_SAMPLE=$(echo "$TOOL_OUTPUT" | tail -5)
fi

ERROR_SIGNATURE=$(echo "$ERROR_SAMPLE" | sed 's/:[0-9]*:/:/g' | sed 's|[^ ]*/[^ ]*/[^ ]*/||g' | sed 's/\[[0-9]*m//g' | sed 's/\x1b//g' | head -c 100)
ERROR_HASH=$(echo -n "$ERROR_SIGNATURE" | python3 -c "import hashlib,sys; print(hashlib.md5(sys.stdin.read().encode()).hexdigest())" 2>/dev/null || echo "unknown")

# Read/initialize state
STATE_FILE=".claude/verify-fix-state.json"
if [ ! -f "$STATE_FILE" ]; then
  STATE_JSON=$(cat <<EOF
{
  "loopActive": true,
  "currentAttempt": 1,
  "maxAttempts": $MAX_RETRY,
  "errorSignatures": {
    "$ERROR_HASH": { "count": 1, "lastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "sample": "$ERROR_SIGNATURE" }
  },
  "startedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastFailure": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  )
else
  STATE_JSON=$(cat "$STATE_FILE")
fi

# Increment attempt counter and error signature count
CURRENT_ATTEMPT=$(echo "$STATE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('currentAttempt',0)+1)" 2>/dev/null || echo 1)

STATE_JSON=$(echo "$STATE_JSON" | python3 <<'PYEOF'
import json, sys, hashlib
from datetime import datetime

data = json.load(sys.stdin)
error_hash = sys.argv[1] if len(sys.argv) > 1 else "unknown"
error_sig = sys.argv[2] if len(sys.argv) > 2 else ""

# Increment current attempt
data['currentAttempt'] = data.get('currentAttempt', 0) + 1
data['lastFailure'] = datetime.utcnow().isoformat() + 'Z'

# Update error signature count
if error_hash not in data.get('errorSignatures', {}):
  data['errorSignatures'][error_hash] = {
    "count": 1,
    "lastSeen": datetime.utcnow().isoformat() + 'Z',
    "sample": error_sig[:200]
  }
else:
  data['errorSignatures'][error_hash]['count'] += 1
  data['errorSignatures'][error_hash]['lastSeen'] = datetime.utcnow().isoformat() + 'Z'

print(json.dumps(data, indent=2))
PYEOF
)

# Write state back
mkdir -p ".claude"
echo "$STATE_JSON" > "$STATE_FILE"

# Check circuit breakers
ERROR_COUNT=$(echo "$STATE_JSON" | python3 -c "import json,sys,sys as s; d=json.load(sys.stdin); h='$ERROR_HASH'; print(d['errorSignatures'].get(h,{}).get('count',0))" 2>/dev/null || echo 0)

# Decision logic
if [ "$ERROR_COUNT" -ge "$NO_PROGRESS_THRESHOLD" ]; then
  # Same error too many times → escalate
  REASON="[VerifyFixLoop] NO_PROGRESS: Same error ($ERROR_HASH) seen $ERROR_COUNT times. Escalating to user."
  REASON_ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$REASON_ESCAPED"
  exit 0
fi

if [ "$CURRENT_ATTEMPT" -ge "$MAX_RETRY" ]; then
  # Max retries exhausted → force accept
  REASON="[VerifyFixLoop] MAX_RETRIES: Exhausted $MAX_RETRY attempts. Returning control to user."
  REASON_ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$REASON_ESCAPED"
  exit 0
fi

# Under thresholds: emit recovery context for /build-fix
CONTEXT_MSG="VERIFY-FIX LOOP [Attempt $CURRENT_ATTEMPT/$MAX_RETRY]: Build/test failed. Error: $ERROR_SIGNATURE. Action: Run /build-fix with this error context, then re-run /verify. Do NOT stop — this is an automated recovery cycle."
CONTEXT_MSG_ESCAPED=$(echo "$CONTEXT_MSG" | sed 's/"/\\"/g')

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$CONTEXT_MSG_ESCAPED"

exit 0
