#!/usr/bin/env bash
#
# Java Compile Check Hook
# Runs compilation check after Java file edits
#

# Profile gate
source "$(dirname "$0")/run-with-flags.sh" "java-compile-check" || exit 0

# Read stdin
DATA=$(cat)

# Get file path from JSON input
FILE_PATH=$(echo "$DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    echo "$DATA"
    exit 0
fi

# Check if it's a Java file
if [[ ! "$FILE_PATH" =~ \.java$ ]]; then
    echo "$DATA"
    exit 0
fi

# Find project root (where build.gradle is)
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

# Run compile check with Gradle (timeout 30s to prevent hanging)
# macOS lacks GNU timeout; fall back to perl-based equivalent if needed
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
else
    echo "$DATA"
    exit 0
fi

# Extract errors related to the edited file
FILENAME=$(basename "$FILE_PATH")
ERRORS=$(echo "$RESULT" | grep -i "error:" | grep -i "$FILENAME" | head -5)

if [ -n "$ERRORS" ]; then
    echo "[Hook] Compilation errors in $FILE_PATH:" >&2
    echo "$ERRORS" >&2
fi

echo "$DATA"
exit 0
