#!/usr/bin/env bash
# =============================================================================
# git-guard.sh — PreToolUse Git Commit/Push Guard (v3.2)
# =============================================================================
# Detects git commit/push commands in Bash tool calls and BLOCKS them.
# Fires on: PreToolUse (Bash)
#
# CLAUDE.md Hard Block #9: "Agent commits to git → FORBIDDEN, only user commits"
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "git-guard" || exit 0

DATA=$(cat)

# Extract command from Bash tool input
COMMAND=$(echo "$DATA" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

if [ -z "$COMMAND" ]; then
  echo "$DATA"
  exit 0
fi

# Check for git commit or push — BLOCK (not just warn)
if echo "$COMMAND" | grep -qE 'git\s+(commit|push|rebase|reset\s+--hard|force-push)'; then
  REASON="[GitGuard] BLOCKED: Agent must not run git commit/push/rebase/reset — only the user commits. Hard Block #9."
  REASON_ESCAPED=$(printf '%s' "$REASON" | sed 's/"/\\"/g')
  printf '{"decision":"block","reason":"%s"}' "$REASON_ESCAPED"
  exit 2
fi

# git add, git status, git diff, git log etc. are allowed
echo "$DATA"
exit 0
