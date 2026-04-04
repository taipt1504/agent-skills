#!/usr/bin/env bash
# =============================================================================
# run-tests.sh — Run all bats-core hook tests
# =============================================================================
# Usage: ./tests/run-tests.sh [--verbose] [test-file.bats]
# Requires: bats-core (https://github.com/bats-core/bats-core)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERBOSE=""

# Parse args
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE="--verbose-run" ;;
    *.bats) SPECIFIC_TEST="$arg" ;;
  esac
done

# Check bats is installed
if ! command -v bats &>/dev/null; then
  echo "Error: bats-core is not installed."
  echo "Install: npm install -g bats"
  echo "     or: brew install bats-core"
  echo "     or: git clone https://github.com/bats-core/bats-core.git && cd bats-core && ./install.sh /usr/local"
  exit 1
fi

echo "=== Running hook tests ==="
echo ""

if [ -n "${SPECIFIC_TEST:-}" ]; then
  bats $VERBOSE "$SCRIPT_DIR/hooks/$SPECIFIC_TEST"
else
  bats $VERBOSE "$SCRIPT_DIR/hooks/"*.bats
fi

echo ""
echo "=== All tests passed ==="
