#!/usr/bin/env bash
# =============================================================================
# git-guard.sh — PreToolUse Git Commit/Push Guard (v3.0)
# =============================================================================
# Detects git commit/push commands in Bash tool calls and warns.
# Fires on: PreToolUse (Bash)
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "git-guard" || exit 0

DATA=$(cat)

# Extract command from Bash tool input
COMMAND=$(echo "$DATA" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

if [ -z "$COMMAND" ]; then
  echo "$DATA"
  exit 0
fi

# Check for git commit or push
if echo "$COMMAND" | grep -qE 'git\s+(commit|push)'; then
  echo "[GitGuard] WARNING: Agent should not run git commit/push — only the user commits. If the user explicitly requested this, proceed." >&2
fi

echo "$DATA"
exit 0
