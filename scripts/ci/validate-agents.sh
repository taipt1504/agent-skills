#!/usr/bin/env bash
# =============================================================================
# validate-agents.sh — Validate all agent definition files
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_DIR="$REPO_ROOT/agents"

ERRORS=0
CHECKED=0

echo "Validating agents in $AGENTS_DIR..."

for agent_file in "$AGENTS_DIR"/*.md; do
  [ -f "$agent_file" ] || continue
  CHECKED=$((CHECKED + 1))
  filename="$(basename "$agent_file")"

  # Check YAML frontmatter exists (starts with ---)
  if ! head -1 "$agent_file" | grep -q '^---$'; then
    echo "  FAIL: $filename — missing YAML frontmatter"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Extract frontmatter (between first and second ---) — macOS compatible
  frontmatter="$(awk 'BEGIN{found=0} /^---$/{found++; next} found==1{print} found>=2{exit}' "$agent_file")"

  # Check required fields
  for field in name description model; do
    if ! echo "$frontmatter" | grep -q "^${field}:"; then
      echo "  FAIL: $filename — missing required field: $field"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Check model is valid
  model="$(echo "$frontmatter" | grep '^model:' | sed 's/model:\s*//' | tr -d ' ')"
  if [ -n "$model" ]; then
    case "$model" in
      opus|sonnet|haiku) ;;
      *)
        echo "  FAIL: $filename — invalid model: $model (must be opus|sonnet|haiku)"
        ERRORS=$((ERRORS + 1))
        ;;
    esac
  fi

  # Check tools field exists
  if ! echo "$frontmatter" | grep -q "^tools:"; then
    echo "  FAIL: $filename — missing required field: tools"
    ERRORS=$((ERRORS + 1))
  fi

  # Check description is non-empty
  desc="$(echo "$frontmatter" | grep '^description:' | sed 's/description:\s*//')"
  if [ -z "$desc" ]; then
    # Could be multi-line description
    if ! echo "$frontmatter" | grep -q 'description: >'; then
      echo "  WARN: $filename — description appears empty"
    fi
  fi
done

echo ""
echo "Agents checked: $CHECKED, Errors: $ERRORS"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi

echo "All agent validations passed."
exit 0
