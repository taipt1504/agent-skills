#!/usr/bin/env bash
# =============================================================================
# validate-hooks.sh — Validate hook configuration and scripts
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/scripts/hooks"

ERRORS=0
WARNINGS=0

echo "Validating hooks..."

# 1. Check hooks/hooks.json is valid JSON
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
if [ -f "$HOOKS_JSON" ]; then
  if ! python3 -c "import json; json.load(open('$HOOKS_JSON'))" 2>/dev/null && \
     ! node -e "JSON.parse(require('fs').readFileSync('$HOOKS_JSON','utf8'))" 2>/dev/null; then
    echo "  FAIL: hooks/hooks.json — invalid JSON"
    ERRORS=$((ERRORS + 1))
  else
    echo "  PASS: hooks/hooks.json — valid JSON"
  fi

  # Extract script paths from hooks.json and verify they exist
  # Look for command fields containing script paths
  scripts_referenced="$(grep -oE 'scripts/hooks/[a-z_-]+\.sh' "$HOOKS_JSON" 2>/dev/null | sort -u)"
  for script_path in $scripts_referenced; do
    full_path="$REPO_ROOT/$script_path"
    if [ ! -f "$full_path" ]; then
      echo "  FAIL: hooks.json references $script_path — file not found"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  echo "  WARN: hooks/hooks.json not found"
  WARNINGS=$((WARNINGS + 1))
fi

# 2. Check .claude/settings.json is valid JSON (if exists)
SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"
if [ -f "$SETTINGS_JSON" ]; then
  if ! python3 -c "import json; json.load(open('$SETTINGS_JSON'))" 2>/dev/null && \
     ! node -e "JSON.parse(require('fs').readFileSync('$SETTINGS_JSON','utf8'))" 2>/dev/null; then
    echo "  FAIL: .claude/settings.json — invalid JSON"
    ERRORS=$((ERRORS + 1))
  else
    echo "  PASS: .claude/settings.json — valid JSON"
  fi

  # Extract script paths from settings.json
  scripts_referenced="$(grep -oE 'scripts/hooks/[a-z_-]+\.sh' "$SETTINGS_JSON" 2>/dev/null | sort -u)"
  for script_path in $scripts_referenced; do
    full_path="$REPO_ROOT/$script_path"
    if [ ! -f "$full_path" ]; then
      echo "  FAIL: settings.json references $script_path — file not found"
      ERRORS=$((ERRORS + 1))
    fi
  done
fi

# 3. Check all hook scripts are executable
echo ""
echo "Checking hook scripts in $HOOKS_DIR..."
for script in "$HOOKS_DIR"/*.sh; do
  [ -f "$script" ] || continue
  filename="$(basename "$script")"

  if [ ! -x "$script" ]; then
    echo "  WARN: $filename — not executable (run: chmod +x $script)"
    WARNINGS=$((WARNINGS + 1))
  fi

  # Check script has shebang
  if ! head -1 "$script" | grep -q '^#!/'; then
    echo "  WARN: $filename — missing shebang line"
    WARNINGS=$((WARNINGS + 1))
  fi
done

echo ""
echo "Hook validation: Errors: $ERRORS, Warnings: $WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi

echo "All hook validations passed."
exit 0
