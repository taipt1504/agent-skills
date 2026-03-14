#!/usr/bin/env bash
# =============================================================================
# run-all.sh — Run all CI validation scripts
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
RESULTS=""

run_validator() {
  local name="$1"
  local script="$2"

  echo ""
  echo "================================================================"
  echo "  $name"
  echo "================================================================"

  if bash "$script"; then
    PASS=$((PASS + 1))
    RESULTS="${RESULTS}\n  PASS  $name"
  else
    FAIL=$((FAIL + 1))
    RESULTS="${RESULTS}\n  FAIL  $name"
  fi
}

echo "Running all CI validators..."

run_validator "Agent Definitions" "$SCRIPT_DIR/validate-agents.sh"
run_validator "Skill Directories" "$SCRIPT_DIR/validate-skills.sh"
run_validator "Command Files"     "$SCRIPT_DIR/validate-commands.sh"
run_validator "Hook Configuration" "$SCRIPT_DIR/validate-hooks.sh"

echo ""
echo "================================================================"
echo "  SUMMARY"
echo "================================================================"
printf "$RESULTS\n"
echo ""
echo "  Total: $((PASS + FAIL)) validators, $PASS passed, $FAIL failed"
echo "================================================================"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "CI VALIDATION: FAIL"
  exit 1
fi

echo ""
echo "CI VALIDATION: PASS"
exit 0
