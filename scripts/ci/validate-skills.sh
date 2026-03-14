#!/usr/bin/env bash
# =============================================================================
# validate-skills.sh — Validate all skill directories
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

ERRORS=0
WARNINGS=0
CHECKED=0

echo "Validating skills in $SKILLS_DIR..."

for skill_dir in "$SKILLS_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  CHECKED=$((CHECKED + 1))
  dirname="$(basename "$skill_dir")"
  skill_file="$skill_dir/SKILL.md"

  # Check SKILL.md exists
  if [ ! -f "$skill_file" ]; then
    echo "  FAIL: $dirname/ — missing SKILL.md"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check YAML frontmatter exists
  if ! head -1 "$skill_file" | grep -q '^---$'; then
    echo "  FAIL: $dirname/SKILL.md — missing YAML frontmatter"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Extract frontmatter — macOS compatible
  frontmatter="$(awk 'BEGIN{found=0} /^---$/{found++; next} found==1{print} found>=2{exit}' "$skill_file")"

  # Check required fields: name, description
  for field in name description; do
    if ! echo "$frontmatter" | grep -q "^${field}:"; then
      echo "  FAIL: $dirname/SKILL.md — missing required field: $field"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Check file size (max 500 lines)
  line_count="$(wc -l < "$skill_file" | tr -d ' ')"
  if [ "$line_count" -gt 500 ]; then
    echo "  WARN: $dirname/SKILL.md — $line_count lines (recommended max: 500)"
    WARNINGS=$((WARNINGS + 1))
  fi

  # Check "When to Activate" section exists
  if ! grep -q "## When to Activate" "$skill_file" 2>/dev/null; then
    echo "  WARN: $dirname/SKILL.md — missing 'When to Activate' section"
    WARNINGS=$((WARNINGS + 1))
  fi
done

echo ""
echo "Skills checked: $CHECKED, Errors: $ERRORS, Warnings: $WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi

echo "All skill validations passed."
exit 0
