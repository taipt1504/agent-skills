#!/usr/bin/env bash
# =============================================================================
# validate-version-sync.sh — Plugin Version Consistency Validator
# =============================================================================
# Ensures the plugin version is identical across all three sources of truth:
#   1. .claude-plugin/plugin.json    (canonical — used by Claude Code)
#   2. package.json                  (npm)
#   3. .claude-plugin/marketplace.json (marketplace entry)
#
# Also flags any hardcoded version banners in scripts that drift from canonical.
#
# Exit codes:
#   0 — versions in sync, no stale prints found
#   1 — version mismatch OR stale print detected
# =============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"
PACKAGE_JSON="$REPO_ROOT/package.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

read_version() {
  local file="$1" path="$2"
  python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
keys = '$path'.split('.')
v = data
for k in keys:
    if k.isdigit():
        v = v[int(k)]
    else:
        v = v[k]
print(v)
" 2>/dev/null
}

CANONICAL=$(read_version "$PLUGIN_JSON" "version")
PKG=$(read_version "$PACKAGE_JSON" "version")
MKT=$(read_version "$MARKETPLACE_JSON" "plugins.0.version")

FAILED=0

echo "Plugin version sync check"
echo "  canonical (.claude-plugin/plugin.json):    $CANONICAL"
echo "  package.json:                              $PKG"
echo "  .claude-plugin/marketplace.json plugin[0]: $MKT"

if [ -z "$CANONICAL" ]; then
  echo -e "${RED}✗ Cannot read canonical version from $PLUGIN_JSON${NC}"
  exit 1
fi

if [ "$PKG" != "$CANONICAL" ]; then
  echo -e "${RED}✗ package.json version ($PKG) != canonical ($CANONICAL)${NC}"
  FAILED=1
fi

if [ "$MKT" != "$CANONICAL" ]; then
  echo -e "${RED}✗ marketplace.json plugin[0].version ($MKT) != canonical ($CANONICAL)${NC}"
  FAILED=1
fi

# Scan setup-kit.sh banner for hardcoded version string
SETUP_KIT="$REPO_ROOT/scripts/setup-kit.sh"
if [ -f "$SETUP_KIT" ]; then
  # Look for any literal "Installer v<digits>" in the banner function — should be ${PLUGIN_VERSION}
  HARDCODED=$(grep -nE 'Installer v[0-9]+\.[0-9]+' "$SETUP_KIT" | grep -v '\${PLUGIN_VERSION}' || true)
  if [ -n "$HARDCODED" ]; then
    echo -e "${RED}✗ setup-kit.sh contains hardcoded version banner:${NC}"
    echo "$HARDCODED"
    echo "  Fix: use \${PLUGIN_VERSION} variable instead"
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}✓ All version sources synced + no stale banners${NC}"
  exit 0
fi

echo ""
echo -e "${YELLOW}Fix: when bumping plugin version, update ALL THREE sources:${NC}"
echo "  - .claude-plugin/plugin.json"
echo "  - package.json"
echo "  - .claude-plugin/marketplace.json (plugins[0].version)"
echo "  Then run this validator to confirm."
exit 1
