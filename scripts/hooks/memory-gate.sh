#!/usr/bin/env bash
# =============================================================================
# memory-gate.sh — PostToolUse Memory Reminder Hook
# =============================================================================
# Fires once per session after the first Edit|Write|MultiEdit tool use.
# Emits a non-blocking reminder to persist learnings via the memory MCP tools.
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "memory-gate" || exit 0

SESSION_ID="${CLAUDE_SESSION_ID:-default}"
FLAG_FILE="${TMPDIR:-/tmp}/claude-memory-gate-${SESSION_ID}"

# --- One-shot gate: only fire once per session ---
if [ -f "$FLAG_FILE" ]; then
  exit 0
fi

# Mark as fired (create flag)
touch "$FLAG_FILE" 2>/dev/null || true

# --- Emit non-blocking additionalContext reminder ---
REMINDER="MEMORY REMINDER: You have not persisted any learning this session. Before ending, use mcp__memory__add_observations to record key decisions and patterns discovered."

# Escape for JSON
REMINDER_ESC="$(printf '%s' "$REMINDER" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')"

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$REMINDER_ESC"
exit 0
