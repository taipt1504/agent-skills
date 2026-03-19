#!/usr/bin/env bash
# =============================================================================
# quality-gate.sh — PostToolUse Quality Gate (v3.0)
# =============================================================================
# After Java file edit: compile check + debug statement check.
# Replaces: java-compile-check.sh + check-debug-statements.sh
# Fires on: PostToolUse (Edit|Write|MultiEdit)
# =============================================================================

source "$(dirname "$0")/run-with-flags.sh" "quality-gate" || exit 0

DATA=$(cat)

# Extract file path
FILE_PATH=$(echo "$DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  echo "$DATA"
  exit 0
fi

# Only check Java files
if [[ ! "$FILE_PATH" =~ \.java$ ]]; then
  echo "$DATA"
  exit 0
fi

FILENAME="$(basename "$FILE_PATH")"

# --- 1. Compile check ---
PROJECT_ROOT="$PWD"
CURRENT_DIR="$PWD"
while [ "$CURRENT_DIR" != "/" ]; do
  if [ -f "$CURRENT_DIR/build.gradle" ] || [ -f "$CURRENT_DIR/build.gradle.kts" ]; then
    PROJECT_ROOT="$CURRENT_DIR"
    break
  fi
  CURRENT_DIR="$(dirname "$CURRENT_DIR")"
done

cd "$PROJECT_ROOT"

_run_with_timeout() {
  if command -v timeout &>/dev/null; then
    timeout 30 "$@"
  elif command -v perl &>/dev/null; then
    perl -e 'alarm 30; exec @ARGV' -- "$@"
  else
    "$@"
  fi
}

if [ -f "gradlew" ]; then
  RESULT=$(_run_with_timeout ./gradlew compileJava --console=plain 2>&1) || RESULT=""
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  RESULT=$(_run_with_timeout gradle compileJava --console=plain 2>&1) || RESULT=""
fi

if [ -n "$RESULT" ]; then
  ERRORS=$(echo "$RESULT" | grep -i "error:" | grep -i "$FILENAME" | head -5)
  if [ -n "$ERRORS" ]; then
    echo "[QualityGate] Compilation errors in $FILE_PATH:" >&2
    echo "$ERRORS" >&2
  fi
fi

# --- 2. Debug statement check ---
if [ -f "$FILE_PATH" ]; then
  if grep -q 'System\.out\.println\|System\.err\.println' "$FILE_PATH" 2>/dev/null; then
    echo "[QualityGate] WARNING: System.out.println found in $FILENAME — use SLF4J" >&2
  fi
  if grep -q '\.printStackTrace()' "$FILE_PATH" 2>/dev/null; then
    echo "[QualityGate] WARNING: printStackTrace() found in $FILENAME — use proper logging" >&2
  fi
  if grep -q '@Disabled' "$FILE_PATH" 2>/dev/null; then
    echo "[QualityGate] INFO: @Disabled test found in $FILENAME" >&2
  fi
fi

echo "$DATA"
exit 0
