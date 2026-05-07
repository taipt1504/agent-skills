#!/usr/bin/env bash
# =============================================================================
# test-non-interactive.sh — verify plugin works in `claude -p` mode
# =============================================================================
# Catches the regression class introduced when skill-router blocks writes the
# agent can't self-resolve in non-interactive sessions. Originally surfaced
# in the v3.3.0 audit (12/12 write-task plugin runs blocked).
#
# Pass: agent completes a write-task without saying "skills-loaded.json" in
# the response.
#
# Requires: `claude` on PATH, network access, an empty test repo, ~$0.30 cost.
# Skip with: SKIP_NONINTERACTIVE=1 (CI default — opt-in via env).
# =============================================================================

set -u

[ "${SKIP_NONINTERACTIVE:-1}" = "1" ] && {
  echo "[skip] non-interactive test (set SKIP_NONINTERACTIVE=0 to run)"
  exit 0
}

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="${TEST_REPO:-/tmp/devco-noninteractive-test}"

# Prepare a minimal Spring-like repo so session-init detects MVC
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/src/main/java/com/example"
cd "$TEST_DIR"
git init -q
cat > build.gradle <<'EOF'
plugins { id 'java' }
dependencies {
  implementation 'org.springframework.boot:spring-boot-starter-web'
}
EOF
cat > src/main/java/com/example/Main.java <<'EOF'
package com.example;
public class Main { public static void main(String[] a) {} }
EOF

# Run a write-task in non-interactive mode
PROMPT='Add a class HelloController in src/main/java/com/example/ with a method hello() returning "ok". One file only.'
echo "[test] running claude -p write-task with plugin loaded..."

OUT=$(claude -p \
  --model sonnet \
  --output-format json \
  --max-budget-usd 0.50 \
  --dangerously-skip-permissions \
  --no-session-persistence \
  --plugin-dir "$PLUGIN_DIR" \
  "$PROMPT" 2>/dev/null) || {
    echo "[fail] claude -p exited non-zero"
    exit 1
  }

# Extract result text
RESULT=$(echo "$OUT" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read(), strict=False).get('result', ''))
except Exception:
    sys.exit(2)
")

# Pass criteria:
#  1. Result must NOT mention skills-loaded.json (would mean hook blocked)
#  2. The HelloController.java file must exist (task completed)
if echo "$RESULT" | grep -qi "skills-loaded\.json"; then
  echo "[FAIL] response mentions skills-loaded.json — skill-router blocked the write."
  echo "       This is the regression that R1 was meant to fix."
  echo "       Verify session-init.sh pre-populates skills-loaded.json."
  echo "--- response ---"
  echo "$RESULT" | head -10
  exit 1
fi

if [ ! -f "$TEST_DIR/src/main/java/com/example/HelloController.java" ]; then
  echo "[FAIL] HelloController.java was NOT created. Task did not complete."
  echo "--- response ---"
  echo "$RESULT" | head -10
  exit 1
fi

echo "[OK] non-interactive write-task completed; file created; no hook block."
rm -rf "$TEST_DIR"
exit 0
