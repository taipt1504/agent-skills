#!/usr/bin/env bash
# =============================================================================
# compact-advisor.sh — Context Monitor & Token Budget Advisor
# =============================================================================
# Monitors tool call count AND estimates token usage for context budget.
# Progressive unloading + real-time token estimation.
# Fires on: PreToolUse (all tools)
#
# Harness Engineering principle: Context is first-class citizen.
# Real measurement > proxy metrics.
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "compact-advisor" || exit 0

trap 'exit 0' ERR

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
# Token Budget Estimation (replaces pure proxy metric)
#
# Empirical baseline (measured 2026-04-24 with claude -p smoke test on
# spring-petclinic, --plugin-dir vs no-plugin delta):
#   - Plugin auto-load delta: ~2,458 tokens
#     (bootstrap/SKILL.md injection ~2,300 + project-profile/config render ~150)
#   - CLAUDE.md (plugin root) does NOT auto-load via --plugin-dir;
#     it reaches context only after `bash scripts/setup.sh` injects it into
#     `.claude/CLAUDE.md`, which Claude Code's native loader then picks up
#     (~1,000 additional tokens when present).
#   - Rules (.claude/rules/*.md): NOT auto-loaded by any hook. Whether
#     Claude Code natively scans .claude/rules/ depends on host version;
#     when it does, ~500 tokens per file.
#   - Domain skills (lazy via Skill tool): ~800 tokens each
#   - Conversation history: ~50 tokens per tool call (rough)
#
# Warning thresholds (of ~200K context budget):
#   70% (~140K): ADVISORY — suggest unloading meta skills
#   85% (~170K): WARNING — unload unused domain skills
#   95% (~190K): CRITICAL — force /compact at next boundary
# ---------------------------------------------------------------------------

# Count loaded skills (approximate from skill-router activity)
SKILLS_LOADED=1  # bootstrap always
RULES_DIR="$PROJECT_ROOT/.claude/rules"
RULES_COUNT=0
[ -d "$RULES_DIR" ] && RULES_COUNT=$(find "$RULES_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

# Empirical baseline (calibrated 2026-04-24):
#   2500 = bootstrap(~2300) + injection wrappers(~150) + project-profile JSON(~50)
#   +1000 if .claude/CLAUDE.md exists (setup.sh-installed plugin CLAUDE.md)
BASELINE_TOKENS=2500
[ -f "$PROJECT_ROOT/.claude/CLAUDE.md" ] && BASELINE_TOKENS=$((BASELINE_TOKENS + 1000))
RULES_TOKENS=$((RULES_COUNT * 500))
SKILLS_ESTIMATE=$((COUNT / 8))  # rough: 1 new skill per 8 tool calls
[ "$SKILLS_ESTIMATE" -gt 10 ] && SKILLS_ESTIMATE=10
SKILLS_TOKENS=$((SKILLS_ESTIMATE * 800))
CONVERSATION_TOKENS=$((COUNT * 50))

TOTAL_ESTIMATED=$((BASELINE_TOKENS + RULES_TOKENS + SKILLS_TOKENS + CONVERSATION_TOKENS))

# Percentage of 200K budget
BUDGET=200000
PERCENT=$((TOTAL_ESTIMATED * 100 / BUDGET))

# ---------------------------------------------------------------------------
# Progressive unloading strategy
#
# Stage 1 (50 calls OR 70%):  Suggest unloading meta skills
# Stage 2 (75 calls OR 85%):  Suggest unloading unused domain skills
# Stage 3 (100 calls OR 95%): Force /compact at workflow boundary
# ---------------------------------------------------------------------------

STAGE2=$((THRESHOLD + 25))
STAGE3=$((THRESHOLD + 50))

STAGE1_FLAG="$TEMP_DIR/claude-compact-stage1-$SESSION_ID"
STAGE2_FLAG="$TEMP_DIR/claude-compact-stage2-$SESSION_ID"
STAGE3_FLAG="$TEMP_DIR/claude-compact-stage3-$SESSION_ID"

if { [ "$COUNT" -ge "$THRESHOLD" ] || [ "$PERCENT" -ge 70 ]; } && [ ! -f "$STAGE1_FLAG" ]; then
  echo "[CompactAdvisor] Stage 1 (${COUNT} calls, ~${PERCENT}% budget): Unload meta skills if not in use (continuous-learning). Consider /compact if transitioning phases." >&2
  touch "$STAGE1_FLAG"
fi

if { [ "$COUNT" -ge "$STAGE2" ] || [ "$PERCENT" -ge 85 ]; } && [ ! -f "$STAGE2_FLAG" ]; then
  echo "[CompactAdvisor] Stage 2 (${COUNT} calls, ~${PERCENT}% budget): Unload unused domain skills. Keep only actively-used skills loaded." >&2
  touch "$STAGE2_FLAG"
fi

if { [ "$COUNT" -ge "$STAGE3" ] || [ "$PERCENT" -ge 95 ]; } && [ ! -f "$STAGE3_FLAG" ]; then
  echo "[CompactAdvisor] CRITICAL Stage 3 (${COUNT} calls, ~${PERCENT}% budget): Run /compact NOW at next workflow boundary (after VERIFY or REVIEW). Preserve: current phase, plan summary, spec summary." >&2
  touch "$STAGE3_FLAG"
fi

# Recurring reminder every 25 calls after stage 3
if [ "$COUNT" -gt "$STAGE3" ] && [ $((COUNT % 25)) -eq 0 ]; then
  echo "[CompactAdvisor] ${COUNT} calls (~${PERCENT}% budget) — context is stale. Run /compact to free context window." >&2
fi

# Persist token estimate for /dc-status --metrics
METRICS_FILE="$PROJECT_ROOT/.claude/sessions/session-metrics.json"
if [ -f "$METRICS_FILE" ]; then
  TOTAL_ESTIMATED="$TOTAL_ESTIMATED" PERCENT="$PERCENT" python3 -c "
import json, os
try:
    with open('$METRICS_FILE') as f:
        m = json.load(f)
    m['estimatedTokens'] = int(os.environ['TOTAL_ESTIMATED'])
    m['budgetPercent'] = int(os.environ['PERCENT'])
    with open('$METRICS_FILE', 'w') as f:
        json.dump(m, f, indent=2)
except:
    pass
" 2>/dev/null || true
fi

exit 0
