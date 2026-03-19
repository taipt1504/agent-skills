#!/usr/bin/env bash
# =============================================================================
# validate-skills.sh — Validate all skill directories (v3.0)
# =============================================================================
# Supports 3-tier structure: bootstrap/, generic/, summer/, meta/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

ERRORS=0
WARNINGS=0
CHECKED=0

echo "Validating skills in $SKILLS_DIR (3-tier)..."

# Find all SKILL.md files across all tiers
while IFS= read -r skill_file; do
  [ -f "$skill_file" ] || continue
  CHECKED=$((CHECKED + 1))

  # Get relative path for display
  rel_path="${skill_file#$SKILLS_DIR/}"
  skill_dir="$(dirname "$skill_file")"
  dirname="$(basename "$skill_dir")"

  # Check YAML frontmatter exists
  if ! head -1 "$skill_file" | grep -q '^---$'; then
    echo "  FAIL: $rel_path — missing YAML frontmatter"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Extract frontmatter
  frontmatter="$(awk 'BEGIN{found=0} /^---$/{found++; next} found==1{print} found>=2{exit}' "$skill_file")"

  # Check required fields: name, description
  for field in name description; do
    if ! echo "$frontmatter" | grep -q "^${field}:"; then
      echo "  FAIL: $rel_path — missing required field: $field"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Check file size (max 500 lines for body)
  line_count="$(wc -l < "$skill_file" | tr -d ' ')"
  if [ "$line_count" -gt 500 ]; then
    echo "  WARN: $rel_path — $line_count lines (recommended max: 500)"
    WARNINGS=$((WARNINGS + 1))
  fi

  # Token budget check (rough: words * 1.3 ≈ tokens, body should be ≤800 tokens)
  # Skip bootstrap which has 1500 token budget
  if [ "$dirname" != "bootstrap" ]; then
    word_count="$(wc -w < "$skill_file" | tr -d ' ')"
    est_tokens=$((word_count * 13 / 10))
    if [ "$est_tokens" -gt 1200 ]; then
      echo "  WARN: $rel_path — ~$est_tokens estimated tokens (budget: ≤800 body)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

done < <(find "$SKILLS_DIR" -name "SKILL.md" -type f 2>/dev/null | sort)

echo ""
echo "Skills checked: $CHECKED, Errors: $ERRORS, Warnings: $WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi

echo "All skill validations passed."
exit 0
