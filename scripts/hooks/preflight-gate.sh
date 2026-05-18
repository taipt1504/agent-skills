#!/usr/bin/env bash
# preflight-gate.sh — PreToolUse hook enforcing pre-flight discovery artifact
#
# Fires before workflow commands: /triage /align /brainstorm /plan /spec /build /dc-review
# Detects gate from invocation, requires latest matching artifact in .claude/memory/preflight/.
# Soft-blocks if missing — prints stderr message requiring agent to write artifact first.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
WORKSPACE="${CLAUDE_PROJECT_DIR:-$PWD}"
ARTIFACT_DIR="$WORKSPACE/.claude/memory/preflight"
mkdir -p "$ARTIFACT_DIR"

# Parse tool input from stdin (Claude Code hook protocol)
INPUT=$(cat 2>/dev/null || echo "{}")

# Detect gate from the slash command being invoked
GATE=""
if echo "$INPUT" | grep -qE '"command":[[:space:]]*"[^"]*\b(triage|align|brainstorm|plan|spec|build|dc-review)\b'; then
  for g in triage align brainstorm plan spec build dc-review; do
    if echo "$INPUT" | grep -qE "/${g}\b|\"${g}\""; then
      GATE="$g"
      break
    fi
  done
fi

# Map command → artifact variant name
case "$GATE" in
  triage)      VARIANT="initial" ;;
  align)       VARIANT="align" ;;
  brainstorm)  VARIANT="brainstorm" ;;
  plan)        VARIANT="plan" ;;
  spec)        VARIANT="spec" ;;
  build)       VARIANT="execute" ;;
  dc-review)   VARIANT="review" ;;
  *)           exit 0 ;;  # not a workflow gate; no enforcement
esac

# Trivial lane: light format acceptable for execute + review; other gates skipped per lanes rule
TRIAGE_FILE="$WORKSPACE/.claude/memory/state/current-triage.json"
LANE="standard"
if [[ -f "$TRIAGE_FILE" ]]; then
  LANE=$(grep -o '"lane":[[:space:]]*"[^"]*"' "$TRIAGE_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -1)
fi

# Trivial bypass: only initial + execute + review required
if [[ "$LANE" == "trivial" ]]; then
  case "$VARIANT" in
    align|brainstorm|plan|spec)
      cat <<EOF >&2
[preflight] Trivial lane: gate '${GATE}' is skipped. Proceeding without artifact.
EOF
      exit 0
      ;;
  esac
fi

# Look for latest matching artifact (within last 4 hours = same task session)
LATEST=$(find "$ARTIFACT_DIR" -name "${VARIANT}-*.md" -type f -newermt "4 hours ago" 2>/dev/null | sort | tail -1)

if [[ -z "$LATEST" ]]; then
  TS=$(date +%s)
  cat <<EOF >&2
[preflight] MANDATORY — gate='${GATE}' (variant=${VARIANT}, lane=${LANE})

Produce pre-flight artifact BEFORE proceeding:
  Path: ${ARTIFACT_DIR}/${VARIANT}-${TS}.md
  Required content (per skills/preflight/SKILL.md §"Step 5"):
    - Enumerate ALL skills (find skills -name SKILL.md) with relevance score 0-100%
    - Enumerate ALL rules (find rules -name '*.md') with relevance score 0-100%
    - APPLY or SKIP per item; SKIP needs concrete evidence
    - Trivial lane: use light 3-5 line format

Read available skills/rules via scripts/hooks/preflight-discovery.sh output (injected above this message).
EOF
  exit 2  # soft block — agent reads stderr, knows to produce artifact
fi

echo "[preflight] gate='${GATE}' using artifact: $(basename "$LATEST")" >&2
exit 0
