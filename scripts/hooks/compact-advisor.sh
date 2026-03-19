#!/usr/bin/env bash
# =============================================================================
# compact-advisor.sh — Context Monitor & Compact Advisor (v3.0)
# =============================================================================
# Monitors tool call count, suggests compact at workflow boundaries.
# Replaces: suggest-compact.sh
# Fires on: PreToolUse
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "compact-advisor" || exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$PROJECT_ROOT" 2>/dev/null || true

SESSION_ID="${CLAUDE_SESSION_ID:-$(echo "$(pwd)" | cksum | cut -d' ' -f1)}"
TEMP_DIR="${TMPDIR:-/tmp}"
COUNTER_FILE="$TEMP_DIR/claude-tool-count-$SESSION_ID"
THRESHOLD="${COMPACT_THRESHOLD:-50}"

# Read or initialize counter
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE")
  COUNT=$((COUNT + 1))
else
  COUNT=1
fi

echo "$COUNT" > "$COUNTER_FILE"

# ---------------------------------------------------------------------------
# Progressive unloading strategy (Section 3.3 — Anti-Context-Rot)
#
# Stage 1 (50 calls):  Suggest unloading meta skills (learning, evolve)
# Stage 2 (75 calls):  Suggest unloading unused domain skills
# Stage 3 (100 calls): Suggest full /compact at workflow boundary
# ---------------------------------------------------------------------------

if [ "$COUNT" -eq "$THRESHOLD" ]; then
  echo "[CompactAdvisor] ${THRESHOLD} tool calls — Stage 1: Unload meta skills if not in use (continuous-learning). Consider /compact if transitioning phases." >&2
fi

STAGE2=$((THRESHOLD + 25))
if [ "$COUNT" -eq "$STAGE2" ]; then
  echo "[CompactAdvisor] ${STAGE2} tool calls — Stage 2: Unload unused domain skills (skills not referenced in last 20 tool calls). Keep only actively-used skills loaded." >&2
fi

STAGE3=$((THRESHOLD + 50))
if [ "$COUNT" -eq "$STAGE3" ]; then
  echo "[CompactAdvisor] ${STAGE3} tool calls — Stage 3: Context likely >70%. Run /compact NOW at next workflow boundary (after VERIFY or REVIEW). Preserve: current phase, plan summary, spec summary, failing tests." >&2
fi

# Recurring reminder every 25 calls after stage 3
if [ "$COUNT" -gt "$STAGE3" ] && [ $((COUNT % 25)) -eq 0 ]; then
  echo "[CompactAdvisor] ${COUNT} tool calls — context is stale. Run /compact to free context window." >&2
fi

exit 0
