#!/usr/bin/env bash
# =============================================================================
# validate-commands.sh — Validate all command files
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMANDS_DIR="$REPO_ROOT/commands"
AGENTS_DIR="$REPO_ROOT/agents"

ERRORS=0
WARNINGS=0
CHECKED=0

echo "Validating commands in $COMMANDS_DIR..."

for cmd_file in "$COMMANDS_DIR"/*.md; do
  [ -f "$cmd_file" ] || continue
  CHECKED=$((CHECKED + 1))
  filename="$(basename "$cmd_file")"

  # Check has top-level heading
  if ! grep -q '^# ' "$cmd_file"; then
    echo "  FAIL: $filename — missing top-level heading (# Title)"
    ERRORS=$((ERRORS + 1))
  fi

  # Check agent references point to existing files
  # Look for patterns like: agent name references (planner, architect, etc.)
  for agent_ref in $(grep -oE '\b(planner|spec-writer|implementer|reviewer|build-fixer|test-runner|database-reviewer|refactorer)\b' "$cmd_file" 2>/dev/null | sort -u); do
    if [ ! -f "$AGENTS_DIR/${agent_ref}.md" ]; then
      echo "  WARN: $filename — references agent '$agent_ref' but $AGENTS_DIR/${agent_ref}.md not found"
      WARNINGS=$((WARNINGS + 1))
    fi
  done

  # Check file is not empty (beyond just a heading)
  line_count="$(wc -l < "$cmd_file" | tr -d ' ')"
  if [ "$line_count" -lt 5 ]; then
    echo "  WARN: $filename — very short ($line_count lines)"
    WARNINGS=$((WARNINGS + 1))
  fi
done

echo ""
echo "Commands checked: $CHECKED, Errors: $ERRORS, Warnings: $WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi

echo "All command validations passed."
exit 0
