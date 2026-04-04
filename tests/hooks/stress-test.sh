#!/usr/bin/env bash
# =============================================================================
# stress-test.sh — Hook performance stress test
# =============================================================================
# Runs each hook N times and measures execution time.
# Target: each hook must complete in <100ms (quality-gate allowed <2s with compile).
# Usage: ./tests/hooks/stress-test.sh [iterations=50]
# =============================================================================

set -euo pipefail

ITERATIONS="${1:-50}"
HOOK_DIR="$(cd "$(dirname "$0")/../../scripts/hooks" && pwd)"
TEMP_DIR="$(mktemp -d)"
PROJECT_DIR="$TEMP_DIR/project"
mkdir -p "$PROJECT_DIR/.claude"
cd "$PROJECT_DIR"

# Setup minimal project
cat > "$PROJECT_DIR/.claude/devco-config.json" << 'EOF'
{ "hooks": { "profile": "standard" } }
EOF

cat > "$PROJECT_DIR/src/main/java/Test.java" << 'EOF'
public class Test { public String run() { return "ok"; } }
EOF
mkdir -p "$PROJECT_DIR/src/main/java"
mv "$PROJECT_DIR/src/main/java/Test.java" "$PROJECT_DIR/src/main/java/Test.java" 2>/dev/null || true

export HOOK_PROFILE="standard"

# Hooks to test (excludes session-init/session-save which have side effects)
HOOKS_FAST=(
  "git-guard.sh"
  "skill-router.sh"
  "compact-advisor.sh"
  "workflow-tracker.sh"
  "observability-trace.sh"
  "build-checkpoint.sh"
  "verify-fix-loop.sh"
)

# Quality gate tested separately (slower due to compile)
HOOKS_SLOW=(
  "quality-gate.sh"
)

PASS=0
FAIL=0
RESULTS=""

echo "=== Hook Stress Test ==="
echo "Iterations: $ITERATIONS"
echo ""

run_hook_bench() {
  local hook="$1"
  local input="$2"
  local threshold_ms="$3"
  local total_ms=0
  local max_ms=0
  local errors=0

  for i in $(seq 1 "$ITERATIONS"); do
    START=$(date +%s%N)
    echo "$input" | bash "$HOOK_DIR/$hook" > /dev/null 2>&1 || ((errors++)) || true
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    total_ms=$((total_ms + ELAPSED))
    [ "$ELAPSED" -gt "$max_ms" ] && max_ms=$ELAPSED
  done

  local avg_ms=$((total_ms / ITERATIONS))
  local status="PASS"
  if [ "$avg_ms" -gt "$threshold_ms" ]; then
    status="FAIL"
    ((FAIL++))
  else
    ((PASS++))
  fi

  printf "  %-30s avg=%4dms  max=%4dms  errors=%d  [%s] (threshold: %dms)\n" \
    "$hook" "$avg_ms" "$max_ms" "$errors" "$status" "$threshold_ms"
}

# Fast hooks: <100ms threshold
echo "--- Fast hooks (threshold: 100ms) ---"
TOOL_INPUT='{"tool_name":"Edit","file_path":"src/main/java/Test.java"}'
for hook in "${HOOKS_FAST[@]}"; do
  if [ -f "$HOOK_DIR/$hook" ]; then
    run_hook_bench "$hook" "$TOOL_INPUT" 100
  else
    echo "  $hook — SKIP (not found)"
  fi
done

# Git guard with Bash input
echo ""
echo "--- Git guard with blocked command ---"
GIT_INPUT='{"tool_name":"Bash","command":"git commit -m test"}'
run_hook_bench "git-guard.sh" "$GIT_INPUT" 100

# Slow hooks: <2000ms threshold (compile)
echo ""
echo "--- Slow hooks (threshold: 2000ms, reduced iterations) ---"
SLOW_ITERATIONS=$((ITERATIONS / 5))
[ "$SLOW_ITERATIONS" -lt 5 ] && SLOW_ITERATIONS=5
ITERATIONS_BAK="$ITERATIONS"
ITERATIONS="$SLOW_ITERATIONS"
for hook in "${HOOKS_SLOW[@]}"; do
  if [ -f "$HOOK_DIR/$hook" ]; then
    run_hook_bench "$hook" "$TOOL_INPUT" 2000
  else
    echo "  $hook — SKIP (not found)"
  fi
done
ITERATIONS="$ITERATIONS_BAK"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
