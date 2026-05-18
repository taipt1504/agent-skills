#!/usr/bin/env bash
# auto-adr.sh — Stop hook for high-stakes lane ADR check
#
# Per doc 04 Phase 4 + REFACTOR_PLAN §2.5 NEW hook.
# Fires at session end. If lane=high-stakes AND no ADR created this session,
# prompts user via stderr to write ADR before completing.

set -euo pipefail

source "$(dirname "$0")/run-with-flags.sh" "auto-adr" || exit 0

WORKSPACE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
TRIAGE_FILE="$WORKSPACE/.claude/memory/state/current-triage.json"
ADR_DIR="$WORKSPACE/docs/adr"
SESSION_MARKER="$WORKSPACE/.claude/memory/state/session-start"

# 1. Lane check
[ -f "$TRIAGE_FILE" ] || exit 0
LANE=$(grep -o '"lane"[[:space:]]*:[[:space:]]*"[^"]*"' "$TRIAGE_FILE" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ "$LANE" = "high-stakes" ] || exit 0

# 2. ADR existence check (any ADR created/modified after session start)
LATEST_ADR=""
if [ -d "$ADR_DIR" ]; then
  if [ -f "$SESSION_MARKER" ]; then
    LATEST_ADR=$(/usr/bin/find "$ADR_DIR" -name "*.md" -type f -newer "$SESSION_MARKER" ! -name "0000-template.md" 2>/dev/null | /usr/bin/head -1)
  else
    # No session marker — check for any ADR created in last hour
    LATEST_ADR=$(/usr/bin/find "$ADR_DIR" -name "*.md" -type f -mmin -60 ! -name "0000-template.md" 2>/dev/null | /usr/bin/head -1)
  fi
fi

if [ -n "$LATEST_ADR" ]; then
  echo "[auto-adr] ADR found: $(basename "$LATEST_ADR"). ✓" >&2
  exit 0
fi

# 3. Brainstorm artifact for ADR rationale source
BRAINSTORM_DIR="$WORKSPACE/.claude/memory/brainstorm-artifacts"
LATEST_BRAINSTORM=""
if [ -d "$BRAINSTORM_DIR" ]; then
  LATEST_BRAINSTORM=$(/usr/bin/ls -t "$BRAINSTORM_DIR"/*.md 2>/dev/null | /usr/bin/head -1)
fi

# 4. Prompt user
cat <<EOF >&2
[auto-adr] WARNING: high-stakes task with NO ADR this session.

High-stakes decisions should be documented for:
- Future reference (why this option vs rejected alternatives?)
- Onboarding (new team members understand)
- Audit trail (compliance, technical debt review)

ADR template: docs/adr/0000-template.md
EOF

if [ -n "$LATEST_BRAINSTORM" ]; then
  echo "[auto-adr] Brainstorm input: ${LATEST_BRAINSTORM#$WORKSPACE/}" >&2
  echo "[auto-adr] Use it for rationale + rejected alternatives." >&2
fi

echo "[auto-adr] To write ADR now: copy template → docs/adr/NNNN-<decision>.md" >&2

# Soft block — user acknowledges, agent doesn't auto-create ADR (user decides)
exit 1
